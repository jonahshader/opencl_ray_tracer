// #define M_PI (3.14159265358979323846)

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

float getFractal(float x, float y, float z, float w,
  float maxScale, float maxMagnitude, int octaves, unsigned int seed);
unsigned int hash(unsigned int x);

float terrain(float x, float y, float z, float w, int quality);

kernel void renderer(
  const int width, const int height,
  const float xyRot, const float yzRot,
  const float ywRot,
  const float xPos, const float yPos,
  const float zPos, const float wPos,
  const int bigIterations, const int smallIterations,
  const float bigParam, const float smallParam,
  const float t, global uint* output
  )
{
  unsigned int x = get_global_id(0);
  unsigned int y = get_global_id(1);

  float2 center = (float2)(width/2.0f, height/2.0f);
  float maxDimCenter = max(center.x, center.y);

  float4 direction = (float4)((x-center.x)/maxDimCenter, 1.0f, (y-center.y)/maxDimCenter, 0.0f);

  float angle = atan2(direction.z, direction.y) + yzRot;
  float mag = sqrt(direction.z * direction.z + direction.y * direction.y);
  direction.y = cos(angle) * mag;
  direction.z = sin(angle) * mag;

  angle = atan2(direction.y, direction.x) + xyRot;
  mag = sqrt(direction.y * direction.y + direction.x * direction.x);
  direction.x = cos(angle) * mag;
  direction.y = sin(angle) * mag;
  direction = normalize(direction);

  float4 position = (float4)(xPos, yPos, zPos, wPos);
  uchar red = 0;
  uchar green = 0;
  uchar blue = 0;

  float rayMoveMultiplier = terrain(position.x, position.y, position.z, position.w, 4);
  rayMoveMultiplier = rayMoveMultiplier > 0.0f ? rayMoveMultiplier : -rayMoveMultiplier;

  int currentQuality = 1;
  int i;
  for (i = 0; i < bigIterations; i++)
  {
    float terrainVal = terrain(position.x, position.y, position.z, position.w, currentQuality);
    if (terrainVal > 0.0f)
    {
      if (currentQuality > 6)
      {
        // brightness = ((45 - i) / 45.0f) * 255.0f;
        float4 dist = position - (float4)(xPos, yPos, zPos, wPos);
        // dist.magnitud
        red = 255.0f / (1.0f + length(dist) * .01f);
        // red *= (.5f + .5f * sin(position.x) * sin(position.y));
        red *= getFractal(position.x, position.y, position.z, 0.0f, 1.0f, 1.0f, 7, 512598);
        green = red;
        blue = red;
        // brightness = (.5f + .5f * sin(length(dist))) * 255.0f;
        // brightness = max(brightness, (char)(pow(i / 45.0f, 2.0f) * 255.0f));
        break;
      }
      else
      {
        float distToMove = pow(0.5f, currentQuality - 1) * 50.0f;
        if (terrainVal > 0.0f) distToMove = -distToMove;
        position = position + direction * distToMove;
        terrainVal = terrain(position.x, position.y, position.z, position.w, currentQuality);
        if (terrainVal < 0.0f) // if it actually got out of the ground with the above move, then increment currentQuality because it is ready for finer control
        {
          currentQuality++;
        }
      }

    }
    else if (terrainVal < -30.0f)
    {
      // hit sky
      red = 30;
      green = 80;
      blue = 150;
      break;
    }
    else
    {
      float distToMove = pow(0.5f, currentQuality - 1) * 50.0f;
      if (terrainVal > 0.0f) distToMove = -distToMove;
      // float distToMove = -terrainVal * 50.0f;
      // if (terrainVal > 0) terrainVal *= 1.1f;
      // else terrainVal -= 5.1f;
      position = position + direction * distToMove;
    }
  }

  // for (int i = 0; i < bigIterations; i++)
  // {
  //   float terrainVal = terrain(position.x, position.y, position.z, position.w, 8);
  //   if (terrainVal > 0.0f)
  //   {
  //     for (int j = 0; j < smallIterations; j++)
  //     {
  //       float distToMove = -terrain(position.x, position.y, position.z, position.w, 12) * smallParam * pow(.5f, j);
  //       position = position + direction * distToMove * rayMoveMultiplier;
  //     }
  //     // brightness = ((45 - i) / 45.0f) * 255.0f;
  //     float4 dist = position - (float4)(xPos, yPos, zPos, wPos);
  //     // dist.magnitud
  //     brightness = 255.0f / (1.0f + length(dist) * .01f);
  //     // brightness = max(brightness, (char)(pow(i / 45.0f, 2.0f) * 255.0f));
  //     break;
  //   }
  //   else if (terrainVal < -100.0f)
  //   {
  //     break;
  //   }
  //   else
  //   {
  //     // float distToMove = max(sqrt(-terrainVal * 50.0f), 300.0f) + 2.5f;
  //     float distToMove = bigParam;
  //     position = position + direction * distToMove * rayMoveMultiplier;
  //     // position = position + direction * 1.0f;
  //   }
  // }


  // char brightness = (char)(getOctave(x, y, t * 100.0f, 0.0f, 0.05f, 1.0f, 2, 3, 4, 5) * 255.0f);
  // char brightness = (char)(getFractal(x, y, t * 50.0f, 0.0f, 0.01f, 1.0f, 12, 5318) * 255.0f);
  // green = 0;
  output[y * width + x] = blue + (green << 8) + (red << 16);
}

float posToVal(int x, int y, int z, int w, int xOffset, int yOffset, int zOffset, int wOffset)
{
  float bigVal = sin(((x + xOffset) % 1853) * 100.0f + ((y + yOffset) % 3115) * 18025.0f + ((z + zOffset) % 18901) * 6574.0f) * 5647.0f;
  bigVal = bigVal > 0 ? bigVal : -bigVal;
  return bigVal - ((int) bigVal);
}

float smooth(float input)
{
  // return .5f * (1.0f - cos(M_PI * input));
  return input * input * (3.0f - (2.0f * input));
  // return input > 0.5f ? 1.0f : 0.0f;
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

float getFractal(float x, float y, float z, float w, float maxScale, float maxMagnitude, int octaves, unsigned int seed)
{
  unsigned int newSeed = seed;
  float sum = 0.0f;
  float maxValue = 0.0f;
  for (int i = 0; i < octaves; i++)
  {
    float mag = pow(.5f, (float)i);
    unsigned int seed1 = hash(newSeed);
    unsigned int seed2 = hash(seed1);
    unsigned int seed3 = hash(seed2);
    sum += getOctave(x, y, z, w, maxScale/mag, mag,
    seed1, seed2, seed3, 0); // offsets

    maxValue += mag;
  }

  return (sum / maxValue) * maxMagnitude;
}

unsigned int hash(unsigned int x)
{
  x = ((x >> 16) ^ x) * 0x45d9f3b;
  x = ((x >> 16) ^ x) * 0x45d9f3b;
  x = (x >> 16) ^ x;
  return x;
}

float terrain(float x, float y, float z, float w, int quality)
{
  float val = getFractal(x, y, z, 0.0f, 0.01f, 1.0f, quality, 5314);
  val += z * -0.005;
  return val;
}
