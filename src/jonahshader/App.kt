package jonahshader

import com.jogamp.common.nio.Buffers
import com.jogamp.opencl.*
import com.jogamp.opencl.gl.CLGLBuffer
import com.jogamp.opencl.gl.CLGLContext
import com.jogamp.opengl.*
import com.jogamp.opengl.awt.GLCanvas
import com.jogamp.opengl.fixedfunc.GLMatrixFunc
import com.jogamp.opengl.util.Animator
import com.jogamp.opengl.util.awt.TextRenderer
import java.awt.*
import java.awt.event.*
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.util.logging.Level
import java.util.logging.Logger
import kotlin.math.min

class App(private var width: Int, private var height: Int) : GLEventListener {
    companion object {
        const val MAX_PARALLELISM_LEVEL = 8
    }

    private var clContext: CLGLContext? = null
    private lateinit var queues: Array<CLCommandQueue?>
    private lateinit var kernels: Array<CLKernel?>
    private lateinit var programs: Array<CLProgram?>
    private lateinit var probes: CLEventList
    private var pboBuffers: ArrayList<CLGLBuffer<*>>? = null
    private var canvas: GLCanvas = GLCanvas(GLCapabilities(GLProfile.get(GLProfile.GL2)))

    private var slices: Int = 0
    private var drawSeperator = false
    private var buffersInitialized = false
    private var rebuild = false

    private var textRenderer: TextRenderer

    private lateinit var animator: Animator

    private var time = 0f

    init {
        canvas.addGLEventListener(this)
        initSceneInteraction()

        val frame = Frame("JOCL JOGL Raytracer :D")
        frame.addWindowListener(object : WindowAdapter() {
            override fun windowClosing(e: WindowEvent) {
                release(e.window)
            }
        })
        canvas.preferredSize = Dimension(width, height)
        canvas.minimumSize = Dimension(100, 100)
        frame.add(canvas)
        frame.pack()

        frame.isVisible = true

        textRenderer = TextRenderer(frame.font.deriveFont(Font.BOLD, 14f), true, true, null, false)

        animator = Animator(canvas)
        animator.setUpdateFPSFrames(165, null)
    }

    override fun init(drawable: GLAutoDrawable) {
        if (clContext == null) {
            // enable GR error checking using the composable pipeline
            drawable.gl = DebugGL2(drawable.gl.gL2)

            drawable.gl.glFinish()
            initCL(drawable.context)
        }
        animator.start()
    }

    override fun dispose(p0: GLAutoDrawable) {} // i guess nothing ?

    private fun initCL(glCtx: GLContext?) {
        try {
            val platform = CLPlatform.getDefault()
            // SLI on NV platform wasn't very fast (??) uhh
            clContext = if (platform.icdSuffix == "NV") {
                CLGLContext.create(glCtx, platform.getMaxFlopsDevice(CLDevice.Type.GPU))
            } else {
                CLGLContext.create(glCtx, platform, CLDevice.Type.ALL)
            }
            val devices = clContext?.devices

            slices = min(devices!!.size, MAX_PARALLELISM_LEVEL)

            // create command queues for every GPU, init kernels
            queues = arrayOfNulls(slices)
            kernels = arrayOfNulls(slices)
            probes = CLEventList(slices)
            for (i in 0 until slices) {
                queues[i] = devices[i].createCommandQueue(CLCommandQueue.Mode.PROFILING_MODE)
//                    .putWriteBuffer()
            }

            //
            val program = File("CLProgram.cl")

            // load program(s)
            programs = arrayOfNulls(slices)
            for (i in 0 until slices) {
                programs[i] = clContext?.createProgram(FileInputStream(program))
            }
            buildProgram()
        } catch (ex: IOException) {
            Logger.getLogger(javaClass.name).log(Level.SEVERE, "can not find 'CLProgram.cl' in classpath.", ex)
            clContext?.release()
        } catch (ex: CLException) {
            Logger.getLogger(javaClass.name).log(Level.SEVERE, "opencl died lol", ex)
            clContext?.release()
        }
    }

    private fun initView(gl: GL2, width: Int, height: Int) {
        gl.glViewport(0, 0, width, height)
        gl.glMatrixMode(GLMatrixFunc.GL_MODELVIEW)
        gl.glLoadIdentity()
        gl.glMatrixMode(GLMatrixFunc.GL_PROJECTION)
        gl.glLoadIdentity()
        gl.glOrtho(0.0, width.toDouble(), 0.0, height.toDouble(), 0.0, 1.0)
    }

    private fun initPBO(gl: GL) {
        if (pboBuffers != null) {
            val oldPbos = IntArray(pboBuffers!!.size)
            for (i in pboBuffers!!.indices) {
                val buffer = pboBuffers!![i]
                oldPbos[i] = buffer.GLID
                buffer.release()
            }
            gl.glDeleteBuffers(oldPbos.size, oldPbos, 0)
        }
        pboBuffers = ArrayList(slices)
        val pbo = IntArray(slices)
        gl.glGenBuffers(slices, pbo, 0)

        // setup one empty PBO per slice
        for (i in 0 until slices) {
            val size = width * height * Buffers.SIZEOF_INT / slices
            gl.glBindBuffer(GL2ES3.GL_PIXEL_UNPACK_BUFFER, pbo[i])
            gl.glBufferData(GL2ES3.GL_PIXEL_UNPACK_BUFFER, size.toLong(), null, GL2ES2.GL_STREAM_DRAW)
            gl.glBindBuffer(GL2ES3.GL_PIXEL_UNPACK_BUFFER, 0)
            pboBuffers!!.add(clContext!!.createFromGLBuffer(pbo[i], size.toLong(), CLMemory.Mem.WRITE_ONLY))
        }
        buffersInitialized = true
    }

    private fun buildProgram() {
        if (programs[0] != null && rebuild) {
            for (i in programs.indices) {
                val source = programs[i]!!.source
                programs[i]!!.release()
                programs[i] = clContext!!.createProgram(source)
            }
        }

        for (i in programs.indices) {
            val device = queues[i]!!.device
            val configure = programs[i]!!.prepare()
            if (programs.size > 1) {
                configure.forDevice(device)
            }
            println(configure)
            configure.withOption(CLProgram.CompilerOptions.FAST_RELAXED_MATH).build()
        }
        rebuild = false
        for (i in kernels.indices) {
            // init kernel with constants
            kernels[i] = programs[min(i, programs.size)]!!.createCLKernel("renderer")
        }
    }

    private fun setKernelConstants() {
        for (i in 0 until slices) {
            kernels[i]!!.setForce32BitArgs(true)
//                .setArg(2, )
                .setArg(3, pboBuffers!![i])
        }
    }

    override fun display(drawable: GLAutoDrawable) {
        val gl = drawable.gl

        // make sure gl does not use our objects before we start computing
        gl.glFinish()
        if (!buffersInitialized) {
            initPBO(gl)
            setKernelConstants()
        }
        if (rebuild) {
            buildProgram()
            setKernelConstants()
        }
        compute()
        render(gl.gL2)
    }

    // OpenGL :D
    private fun render(gl: GL2) {
        gl.glClear(GL.GL_COLOR_BUFFER_BIT)

        // draw slices
        val sliceWidth = width / slices
        for (i in 0 until slices) {
            val seperatorOffset = if (drawSeperator) i else 0
            gl.glBindBuffer(GL2ES3.GL_PIXEL_UNPACK_BUFFER, pboBuffers!![i].GLID)
            gl.glRasterPos2i(sliceWidth * i + seperatorOffset, 0)
            gl.glDrawPixels(sliceWidth, height, GL.GL_BGRA, GL.GL_UNSIGNED_BYTE, 0)
        }
        gl.glBindBuffer(GL2ES3.GL_PIXEL_UNPACK_BUFFER, 0)

        // draw info text
        textRenderer.beginRendering(width, height, false)
        textRenderer.draw("hello gpu pixel rendering interop :D", 10, height - 15)
        for (i in 0 until slices) {
            val device = queues[i]!!.device
            val event = probes.getEvent(i)
            val start = event.getProfilingInfo(CLEvent.ProfilingCommand.START)
            val end = event.getProfilingInfo(CLEvent.ProfilingCommand.END)
            textRenderer.draw(
                device.type.toString() + i + " "
            + ((end - start) / 1000000.0f).toInt() + "ms @"
            + "32bit", 10, height - (20 + 16 * (slices - i))
            )
        }
        textRenderer.endRendering()
    }

    override fun reshape(drawable: GLAutoDrawable, x: Int, y: Int, width: Int, height: Int) {
        if (this.width == width && this.height == height) return
        this.width = width
        this.height = height
        initPBO(drawable.gl)
        setKernelConstants()
        initView(drawable.gl.gL2, width, height)
    }

    private fun release(window: Window?) {
        clContext?.release()
        window?.dispose()
    }

    private fun initSceneInteraction() {
        val mouseAdapter = object : MouseAdapter() {

            var lastpos = Point()

            override fun mouseDragged(e: MouseEvent) {
                val offsetX = lastpos.x - e.x
                val offsetY = lastpos.y - e.y

                lastpos = e.point

                canvas.display() // re-display image because we just dragged the window and it messes it up lol
            }

            override fun mouseMoved(e: MouseEvent) {
                lastpos = e.point
            }

            override fun mouseWheelMoved(e: MouseWheelEvent) {
                println("Mouse wheel rotation event: ${e.wheelRotation}")
                // todo
            }
        }

        val keyAdapter = object : KeyAdapter() {
            override fun keyPressed(e: KeyEvent) {
                println("Key event: ${e.keyChar}") // there is also keyCode
            }
        }

        canvas.addMouseMotionListener(mouseAdapter)
        canvas.addMouseWheelListener(mouseAdapter)
        canvas.addKeyListener(keyAdapter)
    }

    private fun compute() {
        val sliceWidth = (width / slices.toFloat()).toInt()

        // release all old events, you can't reuse events in OpenCL
        probes.release()

        // start computation
        for (i in 0 until slices) {
            kernels[i]!!.putArg(width).putArg(height)
                .putArg(time).rewind()

            // aquire GL objects, and enqueue a kernel with a probe from the list
            queues[i]!!.putAcquireGLObject(pboBuffers!![i])
                .put2DRangeKernel(kernels[i], 0, 0, sliceWidth.toLong(), height.toLong(), 0, 0, probes)
                .putReleaseGLObject(pboBuffers!![i])
        }

        for (i in 0 until slices) {
            queues[i]!!.finish()
        }

        time += 1/165f
    }
}