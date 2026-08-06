import { BrowserDatamatrixCodeReader } from 'https://esm.sh/@zxing/browser@0.1.5';
import { DecodeHintType } from 'https://esm.sh/@zxing/library@0.21.3';
import {
  decodeImageWithVariants,
  decodeLiveFrame,
  getLivePipelineNames,
  loadImageFromFile,
} from './image-decode.js';

const video = document.getElementById('video');
const viewport = document.getElementById('viewport');
const placeholder = document.getElementById('placeholder');
const scanBadge = document.getElementById('scan-badge');
const scanFrame = document.getElementById('scan-frame');
const scanModeSelect = document.getElementById('scan-mode');
const cameraSelect = document.getElementById('camera-select');
const startBtn = document.getElementById('start-btn');
const stopBtn = document.getElementById('stop-btn');
const torchBtn = document.getElementById('torch-btn');
const statusEl = document.getElementById('status');
const latestResult = document.getElementById('latest-result');
const latestValue = document.getElementById('latest-value');
const emptyState = document.getElementById('empty-state');
const historyList = document.getElementById('history');
const copyBtn = document.getElementById('copy-btn');
const clearBtn = document.getElementById('clear-btn');
const fileInput = document.getElementById('file-input');

const reader = new BrowserDatamatrixCodeReader();
reader.hints.set(DecodeHintType.TRY_HARDER, true);

const scanHistory = [];
const scanCanvas = document.createElement('canvas');
const scanContext = scanCanvas.getContext('2d', { willReadFrequently: true });

let isScanning = false;
let scanLoopActive = false;
let activeStream = null;
let switchingCamera = false;
let torchEnabled = false;
let pipelineIndex = 0;
let lastScannedText = '';
let lastScanTime = 0;
const SCAN_COOLDOWN_MS = 1500;
const SCAN_INTERVAL_MS = 100;
const IOS_CAMERA_RELEASE_DELAY_MS = 350;

function isIOS() {
  return (
    /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
  );
}

function getScanMode() {
  return scanModeSelect.value === 'normal' ? 'normal' : 'hard';
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

function setScanningUi(active) {
  viewport.classList.toggle('is-active', active);
  viewport.classList.toggle('is-scanning', active);
  scanBadge.hidden = !active;
  scanFrame?.classList.toggle('is-animated', active);
}

function feedbackSuccess() {
  viewport.classList.add('is-success-flash');
  window.setTimeout(() => viewport.classList.remove('is-success-flash'), 500);

  if (navigator.vibrate) {
    navigator.vibrate(60);
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
  feedbackSuccess();
  setStatus('Đã quét thành công!', 'success');
}

function buildCameraConstraintAttempts(deviceId, preferBack = true) {
  const attempts = [];

  if (deviceId) {
    attempts.push({ video: { deviceId } });
    attempts.push({ video: { deviceId: { ideal: deviceId } } });
    if (!isIOS()) {
      attempts.push({ video: { deviceId: { exact: deviceId } } });
    }
  } else if (preferBack) {
    attempts.push({ video: { facingMode: 'environment' } });
    attempts.push({ video: { facingMode: { ideal: 'environment' } } });
    if (!isIOS()) {
      attempts.push({
        video: {
          facingMode: 'environment',
          width: { ideal: 1920 },
          height: { ideal: 1080 },
        },
      });
    }
  } else {
    attempts.push({ video: { facingMode: 'user' } });
    attempts.push({ video: { facingMode: { ideal: 'user' } } });
  }

  attempts.push({ video: true });
  return attempts;
}

async function openCameraStream(deviceId, preferBack = true) {
  if (!navigator.mediaDevices?.getUserMedia) {
    throw new Error('Trình duyệt không hỗ trợ truy cập camera.');
  }

  const attempts = buildCameraConstraintAttempts(deviceId, preferBack);
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
  } catch {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Không thể phát video từ camera.')), 5000);
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

function waitForVideoReady() {
  if (video.videoWidth > 0 && video.videoHeight > 0) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Camera không trả về hình ảnh.')), 8000);

    const check = () => {
      if (video.videoWidth > 0 && video.videoHeight > 0) {
        clearTimeout(timeout);
        video.removeEventListener('loadedmetadata', check);
        video.removeEventListener('resize', check);
        resolve();
      }
    };

    video.addEventListener('loadedmetadata', check);
    video.addEventListener('resize', check);
    check();
  });
}

function getActiveDeviceId() {
  const track = activeStream?.getVideoTracks()[0];
  return track?.getSettings()?.deviceId ?? '';
}

function getVideoTrack() {
  return activeStream?.getVideoTracks()[0] ?? null;
}

async function updateTorchAvailability() {
  const track = getVideoTrack();
  if (!track) {
    torchBtn.hidden = true;
    torchBtn.disabled = true;
    return;
  }

  try {
    const capabilities = track.getCapabilities?.();
    const hasTorch = Boolean(capabilities?.torch);
    torchBtn.hidden = !hasTorch;
    torchBtn.disabled = !hasTorch;
    torchBtn.classList.toggle('is-active', hasTorch && torchEnabled);
  } catch {
    torchBtn.hidden = true;
    torchBtn.disabled = true;
  }
}

async function setTorch(enabled) {
  const track = getVideoTrack();
  if (!track) {
    return;
  }

  try {
    await track.applyConstraints({ advanced: [{ torch: enabled }] });
    torchEnabled = enabled;
    torchBtn.classList.toggle('is-active', enabled);
  } catch {
    setStatus('Không thể bật đèn pin trên thiết bị này.', 'error');
  }
}

function syncCameraSelect() {
  const activeDeviceId = getActiveDeviceId();
  if (!activeDeviceId) {
    return;
  }

  const hasOption = Array.from(cameraSelect.options).some(
    (option) => option.value === activeDeviceId,
  );

  if (hasOption) {
    cameraSelect.value = activeDeviceId;
  }
}

async function loadCameras() {
  if (!navigator.mediaDevices?.enumerateDevices) {
    cameraSelect.innerHTML = '<option value="">Không hỗ trợ camera</option>';
    cameraSelect.disabled = true;
    return;
  }

  cameraSelect.innerHTML = '<option value="">Đang tải danh sách camera...</option>';
  cameraSelect.disabled = true;

  try {
    const devices = await navigator.mediaDevices.enumerateDevices();
    const videoDevices = devices.filter((device) => device.kind === 'videoinput');

    if (videoDevices.length === 0) {
      cameraSelect.innerHTML = '<option value="">Không tìm thấy camera</option>';
      return;
    }

    cameraSelect.innerHTML = videoDevices
      .map((device, index) => {
        const label = device.label || `Camera ${index + 1}`;
        return `<option value="${device.deviceId}">${escapeHtml(label)}</option>`;
      })
      .join('');
    cameraSelect.disabled = false;
    syncCameraSelect();
  } catch {
    cameraSelect.innerHTML = '<option value="">Không thể tải danh sách camera</option>';
  }
}

function stopScanLoop() {
  scanLoopActive = false;
}

function drawFrameForScan(cropToCenter) {
  const width = video.videoWidth;
  const height = video.videoHeight;

  if (cropToCenter) {
    const cropX = Math.floor(width * 0.1);
    const cropY = Math.floor(height * 0.1);
    const cropWidth = Math.floor(width * 0.8);
    const cropHeight = Math.floor(height * 0.8);
    scanCanvas.width = cropWidth;
    scanCanvas.height = cropHeight;
    scanContext.drawImage(
      video,
      cropX,
      cropY,
      cropWidth,
      cropHeight,
      0,
      0,
      cropWidth,
      cropHeight,
    );
    return;
  }

  scanCanvas.width = width;
  scanCanvas.height = height;
  scanContext.drawImage(video, 0, 0, width, height);
}

function getNextPipelineName() {
  const pipelines = getLivePipelineNames(getScanMode());
  const pipelineName = pipelines[pipelineIndex % pipelines.length];
  pipelineIndex += 1;
  return pipelineName;
}

function startScanLoop() {
  stopScanLoop();
  scanLoopActive = true;
  pipelineIndex = 0;

  const tick = async () => {
    if (!scanLoopActive || !isScanning) {
      return;
    }

    if (video.videoWidth > 0 && video.videoHeight > 0) {
      const pipelineName = getNextPipelineName();

      try {
        drawFrameForScan(true);
        const result = await decodeLiveFrame(reader, scanCanvas, pipelineName);
        addScanResult(result.getText());
      } catch (error) {
        if (error?.name === 'NotFoundException') {
          try {
            drawFrameForScan(false);
            const fullFrameResult = await decodeLiveFrame(reader, scanCanvas, pipelineName);
            addScanResult(fullFrameResult.getText());
          } catch (fullFrameError) {
            if (fullFrameError?.name !== 'NotFoundException') {
              console.debug('Scan attempt:', fullFrameError.message);
            }
          }
        } else {
          console.debug('Scan attempt:', error.message);
        }
      }
    }

    if (scanLoopActive && isScanning) {
      setTimeout(tick, SCAN_INTERVAL_MS);
    }
  };

  tick();
}

async function releaseCamera() {
  stopScanLoop();

  if (torchEnabled) {
    await setTorch(false).catch(() => {});
  }

  if (activeStream) {
    activeStream.getTracks().forEach((track) => track.stop());
    activeStream = null;
  }

  video.srcObject = null;
  torchBtn.hidden = true;
  torchBtn.disabled = true;

  if (isIOS()) {
    await new Promise((resolve) => setTimeout(resolve, IOS_CAMERA_RELEASE_DELAY_MS));
  }
}

function getCameraErrorMessage(error) {
  if (error?.name === 'NotAllowedError') {
    return 'Quyền truy cập camera bị từ chối. Vui lòng cho phép camera trong Cài đặt > Safari > Camera.';
  }

  if (isConstraintError(error)) {
    return 'Không thể khởi động camera trên thiết bị này. Hãy thử chọn camera khác hoặc dùng chức năng quét từ ảnh.';
  }

  if (error?.name === 'NotFoundError') {
    return 'Không tìm thấy camera trên thiết bị.';
  }

  return error?.message || 'Không thể khởi động camera.';
}

async function startCamera(deviceId, preferBack = true) {
  activeStream = await openCameraStream(deviceId, preferBack);
  await attachStreamToVideo(activeStream);
  await waitForVideoReady();
  await loadCameras();
  await updateTorchAvailability();
}

async function startScanning() {
  if (isScanning) {
    return;
  }

  try {
    await releaseCamera();

    isScanning = true;
    startBtn.disabled = true;
    stopBtn.disabled = false;
    scanModeSelect.disabled = true;
    cameraSelect.disabled = true;
    setScanningUi(true);
    placeholder.textContent = 'Đang khởi động camera...';

    const modeLabel = getScanMode() === 'hard' ? 'dot / tương phản thấp' : 'thường';
    setStatus(`Đang quét (${modeLabel})... Giữ mã trong khung giữa.`, 'scanning');

    const preferBack = !cameraSelect.value;
    await startCamera(cameraSelect.value || undefined, preferBack);
    cameraSelect.disabled = false;
    startScanLoop();
  } catch (error) {
    await releaseCamera();
    isScanning = false;
    startBtn.disabled = false;
    stopBtn.disabled = true;
    scanModeSelect.disabled = false;
    cameraSelect.disabled = false;
    setScanningUi(false);
    setStatus(getCameraErrorMessage(error), 'error');
  }
}

async function switchCamera(deviceId) {
  if (!isScanning || switchingCamera) {
    return;
  }

  switchingCamera = true;
  const previousValue = getActiveDeviceId() || cameraSelect.value;

  try {
    stopScanLoop();
    await releaseCamera();
    setStatus('Đang đổi camera...', 'scanning');
    await startCamera(deviceId, false);
    startScanLoop();
    setStatus('Đang quét... Giữ mã trong khung giữa.', 'scanning');
  } catch (error) {
    cameraSelect.value = previousValue;
    setStatus(getCameraErrorMessage(error), 'error');

    try {
      await startCamera(previousValue || undefined, false);
      startScanLoop();
    } catch {
      await stopScanning();
    }
  } finally {
    switchingCamera = false;
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
  scanModeSelect.disabled = false;
  cameraSelect.disabled = false;
  setScanningUi(false);
  placeholder.textContent = 'Nhấn "Bắt đầu quét" để mở camera';
  setStatus('Đã dừng quét.');
}

async function scanFromFile(file) {
  if (!file) {
    return;
  }

  await stopScanning();
  setStatus('Đang xử lý ảnh với nhiều bộ lọc...', 'scanning');

  try {
    const image = await loadImageFromFile(file);
    const result = await decodeImageWithVariants(reader, image, getScanMode());
    addScanResult(result.getText());
  } catch {
    setStatus(
      'Không tìm thấy mã DataMatrix. Thử chụp gần hơn, tăng ánh sáng hoặc chọn chế độ Dot / tương phản thấp.',
      'error',
    );
  } finally {
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
torchBtn.addEventListener('click', () => {
  setTorch(!torchEnabled);
});
cameraSelect.addEventListener('change', () => {
  if (!isScanning || switchingCamera) {
    return;
  }

  const deviceId = cameraSelect.value;
  if (!deviceId || deviceId === getActiveDeviceId()) {
    return;
  }

  switchCamera(deviceId);
});
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
}
