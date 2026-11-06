package com.giangho.game;

import com.badlogic.gdx.backends.lwjgl3.Lwjgl3Application;
import com.badlogic.gdx.backends.lwjgl3.Lwjgl3ApplicationConfiguration;

/** Chạy tour tự động (nhân vật tự đi/đấm/nhảy) và chụp ảnh vào shots/ để kiểm chứng bằng mắt. */
public class ScreenshotMain {
    public static void main(String[] args) {
        GiangHoGame.TOUR = true;
        Lwjgl3ApplicationConfiguration cfg = new Lwjgl3ApplicationConfiguration();
        cfg.setTitle("Giang Hồ Xóm — Tour");
        cfg.setWindowedMode(960, 540);
        cfg.setForegroundFPS(60);
        new Lwjgl3Application(new GiangHoGame(), cfg);
    }
}
