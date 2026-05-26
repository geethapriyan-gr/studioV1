import android.util.Log
import androidx.media3.common.Effect
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.SingleColorLut

/**
 * Applies color matrix transformation using 3D LUT (Look-Up Table).
 *
 * Supports multiple color matrices that are combined via matrix multiplication.
 * Each matrix must be 4x5 (20 elements) representing RGBA transformation.
 * Uses 33x33x33 LUT size for optimal quality/performance balance.
 *
 * @param videoEffects List to add color effect to
 * @param colorMatrixList List of 4x5 color matrices to apply
 */
@UnstableApi
fun applyColorMatrix(
    videoEffects: MutableList<Effect>,
    colorMatrixList: List<List<Double>>
) {
    if (colorMatrixList.isEmpty()) return

    val combinedMatrix = combineColorMatrices(colorMatrixList)
    if (combinedMatrix.size == 20) {
        val lutSize = 33  // Optimal LUT size for quality/performance
        Log.d(
            RENDER_TAG,
            "Applying color matrix: ${colorMatrixList.size} matrices combined, LUT size=${lutSize}x$lutSize"
        )
        val lutData = generateLutFromColorMatrix(combinedMatrix, lutSize)
        val singleColorLut = SingleColorLut.createFromCube(lutData)
        videoEffects += singleColorLut
    } else {
        Log.w(
            RENDER_TAG,
            "Invalid color matrix size: ${combinedMatrix.size} (expected 20 elements for 4x5 matrix)"
        )
    }
}

/**
 * Generates 3D LUT data from a 4x5 color matrix.
 *
 * Creates a cube of RGB values mapped through the color transformation.
 * Each RGB input coordinate is transformed using the matrix and clamped to valid range.
 *
 * @param matrix 4x5 color transformation matrix (20 elements)
 * @param size LUT cube dimension (typically 33 for 33x33x33 cube)
 * @return 3D array of ARGB integer values
 */
private fun generateLutFromColorMatrix(matrix: List<Double>, size: Int): Array<Array<IntArray>> {
    val lut = Array(size) { Array(size) { IntArray(size) } }
    for (r in 0 until size) {
        for (g in 0 until size) {
            for (b in 0 until size) {
                val rf = r.toDouble() / (size - 1)
                val gf = g.toDouble() / (size - 1)
                val bf = b.toDouble() / (size - 1)

                val rr =
                    (matrix[0] * rf + matrix[1] * gf + matrix[2] * bf + matrix[3]) + (matrix[4] / 255.0)
                val gg =
                    (matrix[5] * rf + matrix[6] * gf + matrix[7] * bf + matrix[8]) + (matrix[9] / 255.0)
                val bb =
                    (matrix[10] * rf + matrix[11] * gf + matrix[12] * bf + matrix[13]) + (matrix[14] / 255.0)

                val rInt = (rr.coerceIn(0.0, 1.0) * 255).toInt()
                val gInt = (gg.coerceIn(0.0, 1.0) * 255).toInt()
                val bInt = (bb.coerceIn(0.0, 1.0) * 255).toInt()

                // Combine RGB into a single ARGB integer
                lut[r][g][b] = (0xFF shl 24) or (rInt shl 16) or (gInt shl 8) or bInt
            }
        }
    }
    return lut
}

/**
 * Multiplies two 4x5 color matrices.
 *
 * Used to combine multiple color transformations into a single matrix.
 *
 * @param m1 First color matrix (20 elements)
 * @param m2 Second color matrix (20 elements)
 * @return Combined color matrix (20 elements)
 */
private fun multiplyColorMatrices(m1: List<Double>, m2: List<Double>): List<Double> {
    val result = MutableList(20) { 0.0 }
    for (i in 0..3) {
        for (j in 0..4) {
            result[i * 5 + j] =
                m1[i * 5 + 0] * m2[0 + j] +
                        m1[i * 5 + 1] * m2[5 + j] +
                        m1[i * 5 + 2] * m2[10 + j] +
                        m1[i * 5 + 3] * m2[15 + j] +
                        if (j == 4) m1[i * 5 + 4] else 0.0
        }
    }
    return result
}

/**
 * Combines multiple color matrices into one through sequential multiplication.
 *
 * @param matrices List of 4x5 color matrices to combine
 * @return Single combined color matrix
 */
private fun combineColorMatrices(matrices: List<List<Double>>): List<Double> {
    if (matrices.isEmpty()) return listOf()
    var result = matrices[0]
    for (i in 1 until matrices.size) {
        result = multiplyColorMatrices(matrices[i], result)
    }
    return result
}
