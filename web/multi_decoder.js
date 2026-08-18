/**
 * Decode DataMatrix song song: zxing-wasm (nhiều binarizer) + rxing-wasm.
 * Tự bọc ZXingWASM.readBarcodes khi mobile_scanner tải xong.
 */
const ZXING_VER = '2.1.0';
const RXING_VER = '0.5.5';

const BINARIZERS = ['LocalAverage', 'GlobalHistogram', 'FixedThreshold', 'BoolCast'];
const CROP_SCALES = [1.0, 0.72, 0.55, 0.38];

/** @type {import('https://cdn.jsdelivr.net/npm/rxing-wasm@0.5.5/rxing_wasm.js') | null} */
let rxing = null;
let rxingInit = null;

const state = {
  patched: false,
  engines: ['zxing', 'rxing'],
};

function loadScript(src) {
  return new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = src;
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error(`Failed to load ${src}`));
    document.head.appendChild(s);
  });
}

async function ensureZxing() {
  if (globalThis.ZXingWASM) return;
  await loadScript(
    `https://cdn.jsdelivr.net/npm/zxing-wasm@${ZXING_VER}/dist/iife/reader/index.js`,
  );
  for (let i = 0; i < 80; i++) {
    if (globalThis.ZXingWASM) return;
    await sleep(50);
  }
  throw new Error('ZXingWASM not available');
}

async function ensureRxing() {
  if (rxing) return rxing;
  if (!rxingInit) {
    rxingInit = import(
      `https://cdn.jsdelivr.net/npm/rxing-wasm@${RXING_VER}/rxing_wasm.js`
    ).then(async (mod) => {
      await mod.default();
      rxing = mod;
      return mod;
    });
  }
  return rxingInit;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function pickZxingDataMatrix(results) {
  if (!results?.length) return null;
  for (const r of results) {
    if (!r?.isValid) continue;
    const fmt = String(r.format || '').toLowerCase();
    if (fmt.includes('datamatrix') || fmt.includes('data_matrix')) {
      const text = r.text;
      if (text) return { text, engine: `zxing:${fmt}` };
    }
  }
  return null;
}

async function decodeZxing(imageData, extra = {}) {
  await ensureZxing();
  const opts = {
    formats: ['DataMatrix'],
    tryHarder: true,
    tryRotate: true,
    tryInvert: true,
    tryDenoise: true,
    tryDownscale: true,
    ...extra,
  };
  const results = await globalThis.ZXingWASM.readBarcodes(imageData, opts);
  return pickZxingDataMatrix(results);
}

async function decodeRxing(imageData, label = 'rxing') {
  const mod = await ensureRxing();
  const luma = mod.convert_imagedata_to_luma(imageData);
  const hints = new mod.DecodeHintDictionary();
  hints.set_hint(mod.DecodeHintTypes.PossibleFormats, 'datamatrix');
  hints.set_hint(mod.DecodeHintTypes.TryHarder, 'true');
  hints.set_hint(mod.DecodeHintTypes.AlsoInverted, 'true');
  try {
    const result = mod.decode_barcode_with_hints(
      luma,
      imageData.width,
      imageData.height,
      hints,
      true,
    );
    const text = result?.text?.();
    if (text) {
      result?.free?.();
      return { text, engine: label };
    }
    result?.free?.();
  } catch (_) {
    // no barcode
  }
  return null;
}

function adjustContrast(imageData, contrast = 1.35, invert = false) {
  const { width, height, data } = imageData;
  const out = new ImageData(width, height);
  const bias = 128 * (1 - contrast);
  for (let i = 0; i < data.length; i += 4) {
    let r = data[i];
    let g = data[i + 1];
    let b = data[i + 2];
    r = Math.min(255, Math.max(0, r * contrast + bias));
    g = Math.min(255, Math.max(0, g * contrast + bias));
    b = Math.min(255, Math.max(0, b * contrast + bias));
    if (invert) {
      r = 255 - r;
      g = 255 - g;
      b = 255 - b;
    }
    out.data[i] = r;
    out.data[i + 1] = g;
    out.data[i + 2] = b;
    out.data[i + 3] = data[i + 3];
  }
  return out;
}

/** Niblack-like local threshold — tốt cho mã chấm / tương phản thấp. */
function niblackThreshold(imageData, window = 15, k = -0.2) {
  const { width, height, data } = imageData;
  const gray = new Float32Array(width * height);
  for (let i = 0, p = 0; i < data.length; i += 4, p++) {
    gray[p] = 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
  }

  const out = new ImageData(width, height);
  const half = Math.floor(window / 2);

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sum = 0;
      let sumSq = 0;
      let count = 0;
      for (let dy = -half; dy <= half; dy++) {
        for (let dx = -half; dx <= half; dx++) {
          const nx = x + dx;
          const ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          const v = gray[ny * width + nx];
          sum += v;
          sumSq += v * v;
          count++;
        }
      }
      const mean = sum / count;
      const std = Math.sqrt(Math.max(0, sumSq / count - mean * mean));
      const threshold = mean + k * std;
      const idx = (y * width + x) * 4;
      const v = gray[y * width + x] < threshold ? 0 : 255;
      out.data[idx] = v;
      out.data[idx + 1] = v;
      out.data[idx + 2] = v;
      out.data[idx + 3] = 255;
    }
  }
  return out;
}

function centerCrop(imageData, scale) {
  if (scale >= 0.99) return imageData;
  const { width, height } = imageData;
  const cw = Math.max(32, Math.round(width * scale));
  const ch = Math.max(32, Math.round(height * scale));
  const sx = Math.floor((width - cw) / 2);
  const sy = Math.floor((height - ch) / 2);
  const canvas = document.createElement('canvas');
  canvas.width = cw;
  canvas.height = ch;
  const ctx = canvas.getContext('2d');
  const tmp = document.createElement('canvas');
  tmp.width = width;
  tmp.height = height;
  tmp.getContext('2d').putImageData(imageData, 0, 0);
  ctx.drawImage(tmp, sx, sy, cw, ch, 0, 0, cw, ch);
  return ctx.getImageData(0, 0, cw, ch);
}

/**
 * Chạy nhiều decoder song song, trả về kết quả đầu tiên thành công.
 * @param {ImageData} imageData
 * @param {{ thorough?: boolean }} options
 */
async function decodeParallel(imageData, options = {}) {
  const thorough = options.thorough === true;
  const tasks = [];

  // zxing — nhiều binarizer song song
  for (const bin of BINARIZERS) {
    tasks.push(
      decodeZxing(imageData, { binarizer: bin }).then((r) =>
        r ? { ...r, engine: `zxing:${bin}` } : Promise.reject(),
      ),
    );
  }

  // rxing — engine Rust/ZXing fork
  tasks.push(decodeRxing(imageData, 'rxing'));

  // preprocessing + decode
  tasks.push(
    decodeRxing(niblackThreshold(imageData), 'rxing:niblack').then((r) =>
      r ? r : Promise.reject(),
    ),
  );
  tasks.push(
    decodeZxing(adjustContrast(imageData, 1.5), { binarizer: 'LocalAverage' }).then(
      (r) => (r ? { ...r, engine: 'zxing:contrast' } : Promise.reject()),
    ),
  );
  tasks.push(
    decodeZxing(adjustContrast(imageData, 1.4, true), {
      binarizer: 'GlobalHistogram',
    }).then((r) => (r ? { ...r, engine: 'zxing:invert' } : Promise.reject())),
  );

  if (thorough) {
    for (const scale of CROP_SCALES) {
      if (scale >= 0.99) continue;
      const cropped = centerCrop(imageData, scale);
      tasks.push(
        decodeZxing(cropped, { binarizer: 'LocalAverage' }).then((r) =>
          r ? { ...r, engine: `zxing:crop${Math.round(scale * 100)}` } : Promise.reject(),
        ),
      );
      tasks.push(
        decodeRxing(cropped, `rxing:crop${Math.round(scale * 100)}`).then((r) =>
          r ? r : Promise.reject(),
        ),
      );
    }
  }

  const settled = await Promise.allSettled(tasks);
  for (const s of settled) {
    if (s.status === 'fulfilled' && s.value?.text) {
      return s.value;
    }
  }
  return null;
}

/**
 * Phiên bản nhanh cho camera live (~3 engine song song).
 */
async function decodeFast(imageData, zxingOptions = {}) {
  const tasks = [
    decodeZxing(imageData, { ...zxingOptions, binarizer: 'LocalAverage' }),
    decodeZxing(imageData, { ...zxingOptions, binarizer: 'GlobalHistogram' }),
    decodeRxing(imageData, 'rxing'),
  ];

  const settled = await Promise.allSettled(
    tasks.map((t) => t.then((r) => (r ? r : Promise.reject()))),
  );
  for (const s of settled) {
    if (s.status === 'fulfilled' && s.value?.text) return s.value;
  }
  return null;
}

function toZxingResults(hit) {
  if (!hit?.text) return [];
  return [
    {
      isValid: true,
      text: hit.text,
      format: 'DataMatrix',
      bytes: null,
      position: {
        topLeft: { x: 0, y: 0 },
        topRight: { x: 0, y: 0 },
        bottomRight: { x: 0, y: 0 },
        bottomLeft: { x: 0, y: 0 },
      },
    },
  ];
}

function patchZxingWrapper() {
  if (!globalThis.ZXingWASM || globalThis.ZXingWASM.__rdParallelWrapped) return;
  const orig = globalThis.ZXingWASM.readBarcodes.bind(globalThis.ZXingWASM);
  globalThis.ZXingWASM.readBarcodes = async (imageData, options) => {
    try {
      const hit = await decodeFast(imageData, options || {});
      if (hit) return toZxingResults(hit);
    } catch (_) {
      // fallback
    }
    return orig(imageData, options);
  };
  globalThis.ZXingWASM.__rdParallelWrapped = true;
  state.patched = true;
  console.info('[ReadDatamatrix] Parallel decode wrapper installed (zxing+rxing)');
}

// Poll until mobile_scanner loads ZXingWASM, then patch.
function startPatchLoop() {
  patchZxingWrapper();
  if (!state.patched) {
    setTimeout(startPatchLoop, 300);
  }
}

globalThis.ReadDatamatrixMultiDecoder = {
  decodeParallel,
  decodeFast,
  ensureZxing,
  ensureRxing,
  patchZxingWrapper,
  get state() {
    return { ...state };
  },
};

startPatchLoop();
ensureRxing().catch(() => {
  console.warn('[ReadDatamatrix] rxing-wasm preload failed — zxing-only fallback');
});
