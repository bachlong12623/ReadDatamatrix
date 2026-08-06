export function cloneImageData(imageData) {
  return new ImageData(
    new Uint8ClampedArray(imageData.data),
    imageData.width,
    imageData.height,
  );
}

export function toGrayscale(imageData) {
  const output = cloneImageData(imageData);
  const { data } = output;

  for (let index = 0; index < data.length; index += 4) {
    const gray = data[index] * 0.299 + data[index + 1] * 0.587 + data[index + 2] * 0.114;
    data[index] = gray;
    data[index + 1] = gray;
    data[index + 2] = gray;
    data[index + 3] = 255;
  }

  return output;
}

export function stretchContrast(imageData) {
  const output = cloneImageData(imageData);
  const { data } = output;
  let min = 255;
  let max = 0;

  for (let index = 0; index < data.length; index += 4) {
    const gray = data[index];
    if (gray < min) min = gray;
    if (gray > max) max = gray;
  }

  const range = Math.max(max - min, 1);
  for (let index = 0; index < data.length; index += 4) {
    const value = ((data[index] - min) * 255) / range;
    data[index] = value;
    data[index + 1] = value;
    data[index + 2] = value;
  }

  return output;
}

export function applyGamma(imageData, gamma) {
  const output = cloneImageData(imageData);
  const { data } = output;
  const inverse = 1 / gamma;
  const lookup = new Uint8Array(256);

  for (let value = 0; value < 256; value += 1) {
    lookup[value] = Math.min(255, Math.round(255 * (value / 255) ** inverse));
  }

  for (let index = 0; index < data.length; index += 4) {
    const value = lookup[data[index]];
    data[index] = value;
    data[index + 1] = value;
    data[index + 2] = value;
  }

  return output;
}

export function sharpen(imageData) {
  const { width, height, data } = imageData;
  const output = cloneImageData(imageData);
  const result = output.data;
  const kernel = [0, -1, 0, -1, 5, -1, 0, -1, 0];

  for (let y = 1; y < height - 1; y += 1) {
    for (let x = 1; x < width - 1; x += 1) {
      let sum = 0;
      let kernelIndex = 0;

      for (let ky = -1; ky <= 1; ky += 1) {
        for (let kx = -1; kx <= 1; kx += 1) {
          const pixelIndex = ((y + ky) * width + (x + kx)) * 4;
          sum += data[pixelIndex] * kernel[kernelIndex];
          kernelIndex += 1;
        }
      }

      const outputIndex = (y * width + x) * 4;
      const value = Math.min(255, Math.max(0, sum));
      result[outputIndex] = value;
      result[outputIndex + 1] = value;
      result[outputIndex + 2] = value;
    }
  }

  return output;
}

function thresholdImage(imageData, threshold) {
  const output = cloneImageData(imageData);
  const { data } = output;

  for (let index = 0; index < data.length; index += 4) {
    const value = data[index] >= threshold ? 255 : 0;
    data[index] = value;
    data[index + 1] = value;
    data[index + 2] = value;
  }

  return output;
}

export function otsuThreshold(imageData) {
  const histogram = new Array(256).fill(0);
  const { data } = imageData;
  const total = data.length / 4;

  for (let index = 0; index < data.length; index += 4) {
    histogram[data[index]] += 1;
  }

  let sum = 0;
  for (let value = 0; value < 256; value += 1) {
    sum += value * histogram[value];
  }

  let sumBackground = 0;
  let weightBackground = 0;
  let maxVariance = 0;
  let threshold = 128;

  for (let value = 0; value < 256; value += 1) {
    weightBackground += histogram[value];
    if (weightBackground === 0) continue;

    const weightForeground = total - weightBackground;
    if (weightForeground === 0) break;

    sumBackground += value * histogram[value];
    const meanBackground = sumBackground / weightBackground;
    const meanForeground = (sum - sumBackground) / weightForeground;
    const variance =
      weightBackground *
      weightForeground *
      (meanBackground - meanForeground) **
      2;

    if (variance > maxVariance) {
      maxVariance = variance;
      threshold = value;
    }
  }

  return thresholdImage(imageData, threshold);
}

export function adaptiveThreshold(imageData, blockSize = 21, constant = 7) {
  const { width, height, data } = imageData;
  const output = cloneImageData(imageData);
  const result = output.data;
  const integral = new Float64Array((width + 1) * (height + 1));
  const half = Math.floor(blockSize / 2);

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const gray = data[(y * width + x) * 4];
      const above = integral[y * (width + 1) + x + 1];
      const left = integral[(y + 1) * (width + 1) + x];
      const diagonal = integral[y * (width + 1) + x];
      integral[(y + 1) * (width + 1) + x + 1] = gray + above + left - diagonal;
    }
  }

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const x1 = Math.max(0, x - half);
      const y1 = Math.max(0, y - half);
      const x2 = Math.min(width - 1, x + half);
      const y2 = Math.min(height - 1, y + half);
      const area = (x2 - x1 + 1) * (y2 - y1 + 1);
      const sum =
        integral[(y2 + 1) * (width + 1) + x2 + 1] -
        integral[y1 * (width + 1) + x2 + 1] -
        integral[(y2 + 1) * (width + 1) + x1] +
        integral[y1 * (width + 1) + x1];
      const mean = sum / area;
      const gray = data[(y * width + x) * 4];
      const value = gray < mean - constant ? 0 : 255;
      const outputIndex = (y * width + x) * 4;
      result[outputIndex] = value;
      result[outputIndex + 1] = value;
      result[outputIndex + 2] = value;
    }
  }

  return output;
}

function morphOperation(imageData, radius, compare) {
  const { width, height, data } = imageData;
  const output = cloneImageData(imageData);
  const result = output.data;

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      let extreme = compare === Math.max ? 0 : 255;

      for (let ky = -radius; ky <= radius; ky += 1) {
        for (let kx = -radius; kx <= radius; kx += 1) {
          const sampleX = Math.min(width - 1, Math.max(0, x + kx));
          const sampleY = Math.min(height - 1, Math.max(0, y + ky));
          const value = data[(sampleY * width + sampleX) * 4];
          extreme = compare(extreme, value);
        }
      }

      const outputIndex = (y * width + x) * 4;
      result[outputIndex] = extreme;
      result[outputIndex + 1] = extreme;
      result[outputIndex + 2] = extreme;
    }
  }

  return output;
}

export function dilate(imageData, radius = 1) {
  return morphOperation(imageData, radius, Math.max);
}

export function erode(imageData, radius = 1) {
  return morphOperation(imageData, radius, Math.min);
}

export function morphClose(imageData, radius = 1) {
  return erode(dilate(imageData, radius), radius);
}

export function applyPipeline(canvas, steps) {
  const context = canvas.getContext('2d', { willReadFrequently: true });
  let imageData = context.getImageData(0, 0, canvas.width, canvas.height);

  for (const step of steps) {
    imageData = step(imageData);
  }

  context.putImageData(imageData, 0, 0);
  return canvas;
}

export const PIPELINES = {
  normal: [
    (imageData) => toGrayscale(imageData),
    (imageData) => stretchContrast(imageData),
    (imageData) => otsuThreshold(imageData),
  ],
  sharpenOtsu: [
    (imageData) => toGrayscale(imageData),
    (imageData) => stretchContrast(imageData),
    (imageData) => sharpen(imageData),
    (imageData) => otsuThreshold(imageData),
  ],
  adaptiveSoft: [
    (imageData) => toGrayscale(imageData),
    (imageData) => stretchContrast(imageData),
    (imageData) => applyGamma(imageData, 0.75),
    (imageData) => adaptiveThreshold(imageData, 17, 5),
  ],
  adaptiveHard: [
    (imageData) => toGrayscale(imageData),
    (imageData) => stretchContrast(imageData),
    (imageData) => sharpen(imageData),
    (imageData) => adaptiveThreshold(imageData, 25, 8),
  ],
  dotPeen: [
    (imageData) => toGrayscale(imageData),
    (imageData) => stretchContrast(imageData),
    (imageData) => sharpen(imageData),
    (imageData) => applyGamma(imageData, 0.65),
    (imageData) => adaptiveThreshold(imageData, 21, 6),
    (imageData) => morphClose(imageData, 1),
  ],
  dotPeenStrong: [
    (imageData) => toGrayscale(imageData),
    (imageData) => stretchContrast(imageData),
    (imageData) => sharpen(imageData),
    (imageData) => applyGamma(imageData, 0.55),
    (imageData) => adaptiveThreshold(imageData, 31, 10),
    (imageData) => morphClose(imageData, 2),
  ],
  lowContrastBright: [
    (imageData) => toGrayscale(imageData),
    (imageData) => applyGamma(imageData, 1.4),
    (imageData) => stretchContrast(imageData),
    (imageData) => otsuThreshold(imageData),
  ],
  lowContrastDark: [
    (imageData) => toGrayscale(imageData),
    (imageData) => applyGamma(imageData, 0.6),
    (imageData) => stretchContrast(imageData),
    (imageData) => adaptiveThreshold(imageData, 19, 4),
  ],
};

export const LIVE_PIPELINES = [
  'normal',
  'sharpenOtsu',
  'adaptiveSoft',
  'adaptiveHard',
  'dotPeen',
  'dotPeenStrong',
  'lowContrastBright',
  'lowContrastDark',
];

export const HARD_PIPELINES = [
  'dotPeen',
  'dotPeenStrong',
  'adaptiveHard',
  'adaptiveSoft',
  'lowContrastDark',
  'lowContrastBright',
  'sharpenOtsu',
  'normal',
];
