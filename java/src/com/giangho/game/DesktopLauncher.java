package com.giangho.game;

import com.badlogic.gdx.backends.lwjgl3.Lwjgl3Application;
import com.badlogic.gdx.backends.lwjgl3.Lwjgl3ApplicationConfiguration;

public class DesktopLauncher {
    public static void main(String[] args) {
        Lwjgl3ApplicationConfiguration cfg = new Lwjgl3ApplicationConfiguration();
        cfg.setTitle("Giang Hồ Xóm (Java + LibGDX)");
        cfg.setWindowedMode(960, 540);
        cfg.setBackBufferConfig(8, 8, 8, 8, 16, 0, 4);
        cfg.setForegroundFPS(60);
        new Lwjgl3Application(new GiangHoGame(), cfg);
    }
}
