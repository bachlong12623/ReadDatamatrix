import {
  HARD_PIPELINES,
  LIVE_PIPELINES,
  PIPELINES,
  applyPipeline,
} from './image-preprocess.js';

const decodeCanvas = document.createElement('canvas');
const decodeContext = decodeCanvas.getContext('2d', { willReadFrequently: true });
const workingCanvas = document.createElement('canvas');
const workingContext = workingCanvas.getContext('2d', { willReadFrequently: true });

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
  workingCanvas.width = sourceCanvas.width;
  workingCanvas.height = sourceCanvas.height;
  workingContext.drawImage(sourceCanvas, 0, 0);
  return applyPipeline(workingCanvas, PIPELINES[pipelineName]);
}

function buildBaseVariants(source) {
  const configs = [
    { paddingRatio: 0.2, scale: 1, rotation: 0 },
    { paddingRatio: 0.2, scale: 2, rotation: 0 },
    { paddingRatio: 0.3, scale: 2, rotation: 0 },
    { paddingRatio: 0.2, scale: 3, rotation: 0 },
    { paddingRatio: 0.15, scale: 4, rotation: 0 },
    { paddingRatio: 0.2, scale: 2, rotation: 90 },
    { paddingRatio: 0.2, scale: 2, rotation: 180 },
    { paddingRatio: 0.2, scale: 2, rotation: 270 },
    { paddingRatio: 0.2, scale: 2, rotation: 0, invert: true },
  ];

  return configs.map((config) => drawOnWhiteCanvas(source, config));
}

function buildPipelineVariants(sourceCanvas, pipelineNames) {
  const variants = [sourceCanvas];

  for (const pipelineName of pipelineNames) {
    variants.push(applyPipelineToCanvas(sourceCanvas, pipelineName));
  }

  return variants;
}

export function buildImageDecodeVariants(image, mode = 'hard') {
  const pipelineNames = mode === 'hard' ? HARD_PIPELINES : LIVE_PIPELINES;
  const variants = [];

  for (const baseVariant of buildBaseVariants(image)) {
    variants.push(...buildPipelineVariants(baseVariant, pipelineNames));
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

export function buildLiveFrameVariant(sourceCanvas, pipelineName) {
  const padded = drawOnWhiteCanvas(sourceCanvas, { paddingRatio: 0.18, scale: 2, rotation: 0 });
  return applyPipelineToCanvas(padded, pipelineName);
}

export async function decodeLiveFrame(reader, sourceCanvas, pipelineName) {
  const variants = [
    sourceCanvas,
    buildLiveFrameVariant(sourceCanvas, pipelineName),
    drawOnWhiteCanvas(sourceCanvas, { paddingRatio: 0.2, scale: 2, rotation: 0 }),
  ];

  let lastError;
  for (const canvas of variants) {
    try {
      return await reader.decodeFromCanvas(canvas);
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
  return mode === 'hard' ? HARD_PIPELINES : LIVE_PIPELINES;
}
