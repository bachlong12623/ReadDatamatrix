const decodeCanvas = document.createElement('canvas');
const decodeContext = decodeCanvas.getContext('2d', { willReadFrequently: true });

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

  return decodeCanvas;
}

function cloneCanvas(sourceCanvas) {
  const canvas = document.createElement('canvas');
  canvas.width = sourceCanvas.width;
  canvas.height = sourceCanvas.height;
  canvas.getContext('2d', { willReadFrequently: true }).drawImage(sourceCanvas, 0, 0);
  return canvas;
}

function binarizeCanvas(canvas) {
  const output = cloneCanvas(canvas);
  const context = output.getContext('2d', { willReadFrequently: true });
  const { width, height } = output;
  const imageData = context.getImageData(0, 0, width, height);
  const { data } = imageData;
  let total = 0;

  for (let index = 0; index < data.length; index += 4) {
    total += data[index] * 0.299 + data[index + 1] * 0.587 + data[index + 2] * 0.114;
  }

  const threshold = total / (data.length / 4);
  for (let index = 0; index < data.length; index += 4) {
    const gray = data[index] * 0.299 + data[index + 1] * 0.587 + data[index + 2] * 0.114;
    const value = gray >= threshold ? 255 : 0;
    data[index] = value;
    data[index + 1] = value;
    data[index + 2] = value;
    data[index + 3] = 255;
  }

  context.putImageData(imageData, 0, 0);
  return output;
}

const IMAGE_DECODE_CONFIGS = [
  { paddingRatio: 0.2, scale: 1, rotation: 0 },
  { paddingRatio: 0.2, scale: 2, rotation: 0 },
  { paddingRatio: 0.3, scale: 2, rotation: 0 },
  { paddingRatio: 0.2, scale: 3, rotation: 0 },
  { paddingRatio: 0.15, scale: 4, rotation: 0 },
  { paddingRatio: 0.25, scale: 2, rotation: 0 },
  { paddingRatio: 0.1, scale: 3, rotation: 0 },
  { paddingRatio: 0.4, scale: 2, rotation: 0 },
  { paddingRatio: 0.2, scale: 2, rotation: 90 },
  { paddingRatio: 0.2, scale: 2, rotation: 180 },
  { paddingRatio: 0.2, scale: 2, rotation: 270 },
  { paddingRatio: 0.2, scale: 2, rotation: 0, invert: true },
];

export function buildImageDecodeVariants(image) {
  const variants = [];

  for (const config of IMAGE_DECODE_CONFIGS) {
    variants.push(drawOnWhiteCanvas(image, config));
    variants.push(binarizeCanvas(drawOnWhiteCanvas(image, config)));
  }

  return variants;
}

export async function decodeImageWithVariants(reader, image) {
  const variants = buildImageDecodeVariants(image);
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

export function buildFrameDecodeVariants(sourceCanvas) {
  const variants = [
    sourceCanvas,
    drawOnWhiteCanvas(sourceCanvas, { paddingRatio: 0.15, scale: 1, rotation: 0 }),
    drawOnWhiteCanvas(sourceCanvas, { paddingRatio: 0.25, scale: 2, rotation: 0 }),
    binarizeCanvas(drawOnWhiteCanvas(sourceCanvas, { paddingRatio: 0.2, scale: 2, rotation: 0 })),
  ];

  for (const rotation of [90, 180, 270]) {
    variants.push(drawOnWhiteCanvas(sourceCanvas, { paddingRatio: 0.2, scale: 2, rotation }));
  }

  return variants;
}

export async function decodeCanvasWithVariants(reader, sourceCanvas) {
  const variants = buildFrameDecodeVariants(sourceCanvas);
  let lastError;

  for (const canvas of variants) {
    try {
      return await reader.decodeFromCanvas(canvas);
    } catch (error) {
      lastError = error;
      if (error?.name !== 'NotFoundException') {
        console.debug('Frame decode attempt:', error.message);
      }
    }
  }

  throw lastError ?? new Error('NotFoundException');
}
