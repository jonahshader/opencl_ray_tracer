package jonahshader;

/*
maven stuff:
    <dependency>
      <groupId>org.jogamp.jocl</groupId>
      <artifactId>jocl-main</artifactId>
      <version>2.3.1</version>
    </dependency>

    <dependency>
      <groupId>org.jogamp.jogl</groupId>
      <artifactId>jogl-all-main</artifactId>
      <version>2.3.1</version>
    </dependency>

    <dependency>
      <groupId>org.jogamp.gluegen</groupId>
      <artifactId>gluegen-rt-main</artifactId>
      <version>2.3.1</version>
    </dependency>
 */

import com.jogamp.opengl.GLProfile;

import javax.swing.*;

public class Launcher {
    public static void main(String[] args) {
        GLProfile.initSingleton();

        SwingUtilities.invokeLater(() -> new App(640, 480));

    }
}
