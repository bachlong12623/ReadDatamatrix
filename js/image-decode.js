import {
  FAST_PIPELINES,
  HARD_PIPELINES,
  LIVE_PIPELINES,
  PIPELINES,
  applyPipeline,
} from './image-preprocess.js';
import {
  CROP_PROFILES,
  ZOOM_LEVELS,
  captureVideoFrame,
  createScanScheduler,
  getCropProfileList,
} from './scan-capture.js';

const decodeCanvas = document.createElement('canvas');
const decodeContext = decodeCanvas.getContext('2d', { willReadFrequently: true });
const workingCanvas = document.createElement('canvas');
const workingContext = workingCanvas.getContext('2d', { willReadFrequently: true });

export { CROP_PROFILES, ZOOM_LEVELS, createScanScheduler, captureVideoFrame };

export function loadImageFromFile(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const image = new Image();

    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('Không thể đọc file ảnh.'));
    };
    image.src = url;
  });
}

function getSourceSize(source) {
  if (source instanceof HTMLImageElement) {
    return {
      width: source.naturalWidth || source.width,
      height: source.naturalHeight || source.height,
    };
  }

  return {
    width: source.width,
    height: source.height,
  };
}

function cloneCanvas(sourceCanvas) {
  const canvas = document.createElement('canvas');
  canvas.width = sourceCanvas.width;
  canvas.height = sourceCanvas.height;
  canvas.getContext('2d', { willReadFrequently: true }).drawImage(sourceCanvas, 0, 0);
  return canvas;
}

function cropSourceToCanvas(source, cropProfile, zoom = 1) {
  const profile = CROP_PROFILES[cropProfile] ?? CROP_PROFILES.square;
  const { width, height } = getSourceSize(source);
  const zoomFactor = Math.max(1, zoom);
  const cropWidth = (width * profile.widthRatio) / zoomFactor;
  const cropHeight = (height * profile.heightRatio) / zoomFactor;
  const cropX = (width - cropWidth) / 2;
  const cropY = (height - cropHeight) / 2;

  decodeCanvas.width = Math.round(cropWidth * zoomFactor);
  decodeCanvas.height = Math.round(cropHeight * zoomFactor);
  decodeContext.fillStyle = '#ffffff';
  decodeContext.fillRect(0, 0, decodeCanvas.width, decodeCanvas.height);
  decodeContext.imageSmoothingEnabled = zoomFactor > 1;
  decodeContext.drawImage(
    source,
    cropX,
    cropY,
    cropWidth,
    cropHeight,
    0,
    0,
    decodeCanvas.width,
    decodeCanvas.height,
  );

  return cloneCanvas(decodeCanvas);
}

function drawOnWhiteCanvas(source, {
  paddingRatio = 0.2,
  scale = 1,
  rotation = 0,
  invert = false,
} = {}) {
  const { width, height } = getSourceSize(source);
  const padding = Math.max(Math.round(Math.min(width, height) * paddingRatio), 12);
  const innerWidth = width * scale;
  const innerHeight = height * scale;
  const paddedWidth = innerWidth + padding * 2;
  const paddedHeight = innerHeight + padding * 2;
  const radians = (rotation * Math.PI) / 180;
  const rotatedWidth = rotation % 180 === 0 ? paddedWidth : paddedHeight;
  const rotatedHeight = rotation % 180 === 0 ? paddedHeight : paddedWidth;

  decodeCanvas.width = rotatedWidth;
  decodeCanvas.height = rotatedHeight;
  decodeContext.fillStyle = '#ffffff';
  decodeContext.fillRect(0, 0, rotatedWidth, rotatedHeight);
  decodeContext.imageSmoothingEnabled = false;
  decodeContext.save();
  decodeContext.translate(rotatedWidth / 2, rotatedHeight / 2);
  decodeContext.rotate(radians);
  decodeContext.filter = invert ? 'invert(1)' : 'none';
  decodeContext.drawImage(
    source,
    -innerWidth / 2,
    -innerHeight / 2,
    innerWidth,
    innerHeight,
  );
  decodeContext.restore();
  decodeContext.filter = 'none';

  return cloneCanvas(decodeCanvas);
}

function applyPipelineToCanvas(sourceCanvas, pipelineName) {
  if (!pipelineName || !PIPELINES[pipelineName]) {
    return sourceCanvas;
  }

  workingCanvas.width = sourceCanvas.width;
  workingCanvas.height = sourceCanvas.height;
  workingContext.drawImage(sourceCanvas, 0, 0);
  return applyPipeline(workingCanvas, PIPELINES[pipelineName]);
}

function getPipelineNames(mode) {
  return mode === 'hard' ? HARD_PIPELINES : LIVE_PIPELINES;
}

function buildImageConfigs(mode) {
  const crops = getCropProfileList('auto');
  const zooms = ZOOM_LEVELS;
  const scales = [1, 2, 3];
  const rotations = [0, 90, 180, 270];
  const configs = [];

  for (const crop of crops) {
    for (const zoom of zooms) {
      for (const scale of scales) {
        for (const rotation of rotations) {
          configs.push({ crop, zoom, scale, rotation, invert: false });
        }
        configs.push({ crop, zoom, scale: scale * 1.5, rotation: 0, invert: true });
      }
    }
  }

  return configs;
}

function buildImageDecodeVariants(image, mode = 'hard') {
  const pipelineNames = getPipelineNames(mode);
  const fastPipelines = [...FAST_PIPELINES, ...pipelineNames.filter((name) => !FAST_PIPELINES.includes(name))];
  const variants = [];
  const seen = new Set();

  const addVariant = (canvas) => {
    const key = `${canvas.width}x${canvas.height}`;
    if (!seen.has(key)) {
      seen.add(key);
      variants.push(canvas);
    }
  };

  for (const config of buildImageConfigs(mode)) {
    const cropped = cropSourceToCanvas(image, config.crop, config.zoom);
    const base = drawOnWhiteCanvas(cropped, {
      paddingRatio: 0.18,
      scale: config.scale,
      rotation: config.rotation,
      invert: config.invert,
    });
    addVariant(base);

    for (const pipelineName of fastPipelines) {
      addVariant(applyPipelineToCanvas(base, pipelineName));
    }
  }

  return variants;
}

export async function decodeImageWithVariants(reader, image, mode = 'hard') {
  const variants = buildImageDecodeVariants(image, mode);
  let lastError;

  for (const canvas of variants) {
    try {
      return await reader.decodeFromCanvas(canvas);
    } catch (error) {
      lastError = error;
      if (error?.name !== 'NotFoundException') {
        console.debug('Image decode attempt:', error.message);
      }
    }
  }

  throw lastError ?? new Error('NotFoundException');
}

export async function decodeLiveAttempt(reader, sourceCanvas, combination) {
  const attempts = [sourceCanvas];

  if (!combination.raw && combination.pipeline) {
    attempts.push(applyPipelineToCanvas(sourceCanvas, combination.pipeline));
    const padded = drawOnWhiteCanvas(sourceCanvas, { paddingRatio: 0.16, scale: 1, rotation: 0 });
    attempts.push(applyPipelineToCanvas(padded, combination.pipeline));
  }

  let lastError;
  for (const canvas of attempts) {
    try {
      const result = await reader.decodeFromCanvas(canvas);
      return { result, combination };
    } catch (error) {
      lastError = error;
      if (error?.name !== 'NotFoundException') {
        console.debug('Live decode attempt:', error.message);
      }
    }
  }

  throw lastError ?? new Error('NotFoundException');
}

export function getLivePipelineNames(mode) {
  return getPipelineNames(mode);
}

export function createLiveScanScheduler(options) {
  return createScanScheduler(options);
}
