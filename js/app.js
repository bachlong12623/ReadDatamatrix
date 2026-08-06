import { BrowserDatamatrixCodeReader } from 'https://esm.sh/@zxing/browser@0.1.5';

const video = document.getElementById('video');
const viewport = document.getElementById('viewport');
const placeholder = document.getElementById('placeholder');
const cameraField = document.querySelector('.field');
const cameraSelect = document.getElementById('camera-select');
const startBtn = document.getElementById('start-btn');
const stopBtn = document.getElementById('stop-btn');
const statusEl = document.getElementById('status');
const latestResult = document.getElementById('latest-result');
const latestValue = document.getElementById('latest-value');
const emptyState = document.getElementById('empty-state');
const historyList = document.getElementById('history');
const copyBtn = document.getElementById('copy-btn');
const clearBtn = document.getElementById('clear-btn');
const fileInput = document.getElementById('file-input');

const reader = new BrowserDatamatrixCodeReader();
const scanHistory = [];
let isScanning = false;
let scannerControls = null;
let activeStream = null;
let lastScannedText = '';
let lastScanTime = 0;
const SCAN_COOLDOWN_MS = 1500;
const IOS_CAMERA_RELEASE_DELAY_MS = 350;

function isIOS() {
  return (
    /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
  );
}

function isConstraintError(error) {
  return (
    error?.name === 'OverconstrainedError' ||
    error?.name === 'ConstraintNotSatisfiedError' ||
    /invalid constraint/i.test(error?.message ?? '')
  );
}

function setStatus(message, type = '') {
  statusEl.textContent = message;
  statusEl.className = 'status';
  if (type) {
    statusEl.classList.add(`is-${type}`);
  }
}

function formatTime(date) {
  return date.toLocaleTimeString('vi-VN', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
}

function renderHistory() {
  if (scanHistory.length === 0) {
    historyList.hidden = true;
    clearBtn.disabled = true;
    return;
  }

  historyList.hidden = false;
  clearBtn.disabled = false;
  historyList.innerHTML = scanHistory
    .map(
      (item, index) => `
        <li class="history__item" data-index="${index}" tabindex="0" role="button">
          <span class="history__text">${escapeHtml(item.text)}</span>
          <span class="history__meta">${formatTime(item.time)}</span>
        </li>
      `,
    )
    .join('');

  historyList.querySelectorAll('.history__item').forEach((el) => {
    const showItem = () => {
      const item = scanHistory[Number(el.dataset.index)];
      showResult(item.text);
    };
    el.addEventListener('click', showItem);
    el.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        showItem();
      }
    });
  });
}

function escapeHtml(text) {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function showResult(text) {
  latestValue.textContent = text;
  latestResult.hidden = false;
  emptyState.hidden = true;
}

function addScanResult(text) {
  const now = Date.now();
  if (text === lastScannedText && now - lastScanTime < SCAN_COOLDOWN_MS) {
    return;
  }

  lastScannedText = text;
  lastScanTime = now;

  showResult(text);
  scanHistory.unshift({ text, time: new Date() });
  if (scanHistory.length > 20) {
    scanHistory.pop();
  }
  renderHistory();
  setStatus('Đã quét thành công!', 'success');
}

function onScanResult(result, error) {
  if (result) {
    addScanResult(result.getText());
  }

  if (error && error.name !== 'NotFoundException') {
    console.debug('Scan attempt:', error.message);
  }
}

function buildCameraConstraintAttempts(deviceId) {
  if (isIOS()) {
    return [{ video: true }];
  }

  const attempts = [{ video: true }];

  if (deviceId) {
    attempts.unshift(
      { video: { deviceId: { ideal: deviceId } } },
      { video: { deviceId } },
      { video: { deviceId: { exact: deviceId } } },
    );
  } else {
    attempts.unshift(
      { video: { facingMode: { ideal: 'environment' } } },
      { video: { facingMode: 'environment' } },
    );
  }

  return attempts;
}

async function openCameraStream(deviceId) {
  if (!navigator.mediaDevices?.getUserMedia) {
    throw new Error('Trình duyệt không hỗ trợ truy cập camera.');
  }

  const attempts = buildCameraConstraintAttempts(deviceId);
  let lastError;

  for (const constraints of attempts) {
    try {
      return await navigator.mediaDevices.getUserMedia(constraints);
    } catch (error) {
      lastError = error;
      if (!isConstraintError(error)) {
        throw error;
      }
    }
  }

  throw lastError ?? new Error('Không thể khởi động camera.');
}

async function attachStreamToVideo(stream) {
  video.srcObject = stream;
  video.muted = true;
  video.playsInline = true;
  video.setAttribute('playsinline', 'true');
  video.setAttribute('webkit-playsinline', 'true');

  try {
    await video.play();
  } catch (error) {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(error), 5000);
      video.addEventListener(
        'loadedmetadata',
        () => {
          video.play().then(resolve).catch(reject).finally(() => clearTimeout(timeout));
        },
        { once: true },
      );
    });
  }
}

async function releaseCamera() {
  if (scannerControls) {
    scannerControls.stop();
    scannerControls = null;
  }

  if (activeStream) {
    activeStream.getTracks().forEach((track) => track.stop());
    activeStream = null;
  }

  video.srcObject = null;

  if (isIOS()) {
    await new Promise((resolve) => setTimeout(resolve, IOS_CAMERA_RELEASE_DELAY_MS));
  }
}

function getCameraErrorMessage(error) {
  if (error?.name === 'NotAllowedError') {
    return 'Quyền truy cập camera bị từ chối. Vui lòng cho phép camera trong Cài đặt > Safari > Camera.';
  }

  if (isConstraintError(error)) {
    return 'Không thể khởi động camera trên thiết bị này. Hãy thử tải lại trang hoặc dùng chức năng quét từ ảnh.';
  }

  if (error?.name === 'NotFoundError') {
    return 'Không tìm thấy camera trên thiết bị.';
  }

  return error?.message || 'Không thể khởi động camera.';
}

async function loadCameras() {
  if (!navigator.mediaDevices?.enumerateDevices) {
    cameraSelect.innerHTML = '<option value="">Không hỗ trợ camera</option>';
    return;
  }

  try {
    const devices = await BrowserDatamatrixCodeReader.listVideoInputDevices();
    if (devices.length === 0) {
      cameraSelect.innerHTML = '<option value="">Không tìm thấy camera</option>';
      cameraSelect.disabled = true;
      return;
    }

    cameraSelect.innerHTML = devices
      .map(
        (device, index) =>
          `<option value="${device.deviceId}">${escapeHtml(device.label || `Camera ${index + 1}`)}</option>`,
      )
      .join('');
    cameraSelect.disabled = false;
  } catch {
    cameraSelect.innerHTML = '<option value="">Không thể truy cập camera</option>';
    cameraSelect.disabled = true;
  }
}

async function requestCameraPermission() {
  const stream = await openCameraStream();
  stream.getTracks().forEach((track) => track.stop());
  await new Promise((resolve) => setTimeout(resolve, isIOS() ? IOS_CAMERA_RELEASE_DELAY_MS : 0));
  await loadCameras();
}

async function startIOSScanning() {
  activeStream = await navigator.mediaDevices.getUserMedia({ video: true });
  await attachStreamToVideo(activeStream);
  scannerControls = await reader.decodeFromVideoElement(video, onScanResult);
}

async function startDesktopScanning(deviceId) {
  activeStream = await openCameraStream(deviceId);
  scannerControls = await reader.decodeFromStream(activeStream, video, onScanResult);
}

async function startScanning() {
  if (isScanning) {
    return;
  }

  try {
    await releaseCamera();

    if (!isIOS() && cameraSelect.disabled) {
      await requestCameraPermission();
    }

    isScanning = true;
    startBtn.disabled = true;
    stopBtn.disabled = false;
    if (!isIOS()) {
      cameraSelect.disabled = true;
    }
    viewport.classList.add('is-active');
    placeholder.textContent = 'Đang khởi động camera...';
    setStatus('Đang quét... Hướng mã DataMatrix vào khung.', 'scanning');

    if (isIOS()) {
      await startIOSScanning();
    } else {
      const deviceId = cameraSelect.value || undefined;
      await startDesktopScanning(deviceId);
    }
  } catch (error) {
    await releaseCamera();
    isScanning = false;
    startBtn.disabled = false;
    stopBtn.disabled = true;
    if (!isIOS()) {
      cameraSelect.disabled = false;
    }
    viewport.classList.remove('is-active');
    setStatus(getCameraErrorMessage(error), 'error');
  }
}

async function stopScanning() {
  if (!isScanning) {
    return;
  }

  await releaseCamera();
  isScanning = false;
  startBtn.disabled = false;
  stopBtn.disabled = true;
  if (!isIOS()) {
    cameraSelect.disabled = false;
  }
  viewport.classList.remove('is-active');
  placeholder.textContent = 'Nhấn "Bắt đầu quét" để mở camera';
  setStatus('Đã dừng quét.');
}

async function scanFromFile(file) {
  if (!file) {
    return;
  }

  await stopScanning();
  setStatus('Đang xử lý ảnh...', 'scanning');

  const url = URL.createObjectURL(file);
  try {
    const result = await reader.decodeFromImageUrl(url);
    addScanResult(result.getText());
  } catch {
    setStatus('Không tìm thấy mã DataMatrix trong ảnh.', 'error');
  } finally {
    URL.revokeObjectURL(url);
    fileInput.value = '';
  }
}

async function copyLatest() {
  const text = latestValue.textContent;
  if (!text) {
    return;
  }

  try {
    await navigator.clipboard.writeText(text);
    setStatus('Đã sao chép vào clipboard.', 'success');
  } catch {
    setStatus('Không thể sao chép. Hãy chọn và sao chép thủ công.', 'error');
  }
}

function clearHistory() {
  scanHistory.length = 0;
  lastScannedText = '';
  renderHistory();
  latestResult.hidden = true;
  emptyState.hidden = false;
  latestValue.textContent = '';
  setStatus('Đã xóa lịch sử.');
}

startBtn.addEventListener('click', startScanning);
stopBtn.addEventListener('click', stopScanning);
copyBtn.addEventListener('click', copyLatest);
clearBtn.addEventListener('click', clearHistory);
fileInput.addEventListener('change', (event) => {
  const file = event.target.files?.[0];
  scanFromFile(file);
});

window.addEventListener('beforeunload', () => {
  if (isScanning) {
    releaseCamera();
  }
});

if (!window.isSecureContext) {
  setStatus(
    'Camera yêu cầu kết nối HTTPS. Hãy mở ứng dụng qua GitHub Pages hoặc localhost.',
    'error',
  );
  startBtn.disabled = true;
} else if (isIOS()) {
  cameraField.hidden = true;
} else {
  loadCameras();
}
