#define M_PI (3.14159265358979323846)

float posToVal(int x, int y, int z, int w,
  int xOffset, int yOffset, int zOffset, int wOffset);

float smooth(float input);

float linear(float x, float x0, float x1);

float bilinear(float x, float y, float x0y0, float x1y0,
                                 float x0y1, float x1y1);

float trilinear(float x, float y, float z,
  float x0y0z0, float x1y0z0, float x0y1z0, float x1y1z0,
  float x0y0z1, float x1y0z1, float x0y1z1, float x1y1z1);

float getOctave(float x, float y, float z, float w,
                float scale, float magnitude,
                int xOffset, int yOffset, int zOffset, int wOffset);

kernel void renderer(
  const int width, const int height,
  const float t, global uint* output
  )
{
  unsigned int x = get_global_id(0);
  unsigned int y = get_global_id(1);

  char brightness = (char)(getOctave(x, y, t * 100.0f, 0.0f, 0.05f, 1.0f, 2, 3, 4, 5) * 255.0f);
  output[y * width + x] = brightness + (brightness << 8) + (brightness << 16) + 0xff000000;
}

float posToVal(int x, int y, int z, int w, int xOffset, int yOffset, int zOffset, int wOffset)
{
  float bigVal = sin((x + xOffset % 1853) * 100.0f + (y + yOffset % 3115) * 18025.0f + (z + zOffset % 18901) * 6574.0f) * 5647.0f;
  bigVal = bigVal > 0 ? bigVal : -bigVal;
  return bigVal - ((int) bigVal);
}

float smooth(float input)
{
  return .5f * (1.0f - cos(M_PI * input));
}

float linear(float x, float x0, float x1)
{
  // return (1.0f-input) * x0 + (input * x1);
  return smooth((1.0f-x) * x0 + (x * x1));
}

float bilinear(float x, float y, float x0y0, float x1y0,
                                 float x0y1, float x1y1)
{
  float y0 = linear(x, x0y0, x1y0);
  float y1 = linear(x, x0y1, x1y1);

  return linear(y, y0, y1);
}

float trilinear(float x, float y, float z,
  float x0y0z0, float x1y0z0, float x0y1z0, float x1y1z0,
  float x0y0z1, float x1y0z1, float x0y1z1, float x1y1z1)
{
  float z0 = bilinear(x, y, x0y0z0, x1y0z0, x0y1z0, x1y1z0);
  float z1 = bilinear(x, y, x0y0z1, x1y0z1, x0y1z1, x1y1z1);

  return linear(z, z0, z1);
}

float getOctave(float x, float y, float z, float w,
                float scale, float magnitude,
                int xOffset, int yOffset, int zOffset, int wOffset)
{
  float xf = x * scale;
  float yf = y * scale;
  float zf = z * scale;
  float wf = w * scale;

  xf += xOffset / 2147483647.0f;
  yf += yOffset / 2147483647.0f;
  zf += zOffset / 2147483647.0f;
  wf += wOffset / 2147483647.0f;

  int xMin = floor(xf);
  int yMin = floor(yf);
  int zMin = floor(zf);
  int wMin = floor(wf);

  int xMax = xMin + 1;
  int yMax = yMin + 1;
  int zMax = zMin + 1;
  int wMax = wMin + 1;

  float xp = xf - xMin;
  float yp = yf - yMin;
  float zp = zf - zMin;
  float wp = wf - wMin;

  float x0y0z0 = posToVal(xMin, yMin, zMin, wMin, xOffset, yOffset, zOffset, wOffset);
  float x1y0z0 = posToVal(xMax, yMin, zMin, wMin, xOffset, yOffset, zOffset, wOffset);
  float x0y1z0 = posToVal(xMin, yMax, zMin, wMin, xOffset, yOffset, zOffset, wOffset);
  float x1y1z0 = posToVal(xMax, yMax, zMin, wMin, xOffset, yOffset, zOffset, wOffset);

  float x0y0z1 = posToVal(xMin, yMin, zMax, wMin, xOffset, yOffset, zOffset, wOffset);
  float x1y0z1 = posToVal(xMax, yMin, zMax, wMin, xOffset, yOffset, zOffset, wOffset);
  float x0y1z1 = posToVal(xMin, yMax, zMax, wMin, xOffset, yOffset, zOffset, wOffset);
  float x1y1z1 = posToVal(xMax, yMax, zMax, wMin, xOffset, yOffset, zOffset, wOffset);

  float outPreMag = trilinear(xp, yp, zp, x0y0z0, x1y0z0, x0y1z0, x1y1z0, x0y0z1, x1y0z1, x0y1z1, x1y1z1);

  return outPreMag * magnitude;
}
