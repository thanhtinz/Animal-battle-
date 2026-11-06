package com.giangho.game;

/** Logic thế giới thuần của Giang Hồ Xóm (bản Java) — port trung thành từ js/world.js.
 *  Không phụ thuộc LibGDX để test bằng main() thường được. */
public class World {
    public static final float MIN_X = -40, MAX_X = 40, MIN_Z = -27, MAX_Z = 27;
    public static final float PLAYER_R = 0.55f;
    public static final float WALK = 6f, RUN = 9.5f, RUN_AT = 0.85f;
    public static final float GRAVITY = -24f, JUMP_V = 8.6f;
    public static final float PUNCH_TIME = 0.32f, GRAB_TIME = 0.45f;

    public static class Obstacle {
        public final float x, z, hw, hd, h; public final String sign; public final int color;
        Obstacle(float x, float z, float hw, float hd, float h, String sign, int color) {
            this.x = x; this.z = z; this.hw = hw; this.hd = hd; this.h = h; this.sign = sign; this.color = color;
        }
    }

    public static final Obstacle[] OBSTACLES = {
        new Obstacle(-30, -21, 7, 4.5f, 9,  "TẠP HÓA",   0xc9552e),
        new Obstacle(-15, -21, 7, 4.5f, 11, "CHỢ MỚI",   0x1f7a6d),
        new Obstacle(  0, -21, 7, 4.5f, 8,  "TRÀ ĐÁ",    0x8a5fb0),
        new Obstacle( 15, -21, 7, 4.5f, 10, "TIỆM CƠM",  0xb03a2e),
        new Obstacle( 30, -21, 7, 4.5f, 9,  "CÀ PHÊ",    0x546e7a),
        new Obstacle(-30,  21, 7, 4.5f, 10, "HỦ TIẾU",   0xa0522d),
        new Obstacle(-15,  21, 7, 4.5f, 8,  "SỬA XE",    0x37474f),
        new Obstacle(  0,  21, 7, 4.5f, 11, "TẠP HÓA 2", 0x2e7d32),
        new Obstacle( 15,  21, 7, 4.5f, 9,  "BÁNH MÌ",   0xd35400),
        new Obstacle( 30,  21, 7, 4.5f, 8,  "NET XÓM",   0x283593),
        new Obstacle( -9,   6, 2.2f, 1.6f, 2.4f, "SẠP",  0x795548),
        new Obstacle( 11,  -6, 2.2f, 1.6f, 2.4f, "SẠP",  0x6d4c41),
    };

    public static class Player {
        public String name;
        public float x, y, z, vy, heading = (float) Math.PI;
        public boolean moving, running, grounded = true;
        public float punchT, grabT, animT;
        Player(String name, float x, float z) { this.name = name; this.x = x; this.z = z; }
    }

    public static Player createPlayer(String name, float x, float z) { return new Player(name, x, z); }

    /** Joystick: dx,dy pixel so với tâm; trả {x, y, mag} sau vùng chết, độ dài <= 1. */
    public static float[] joystickVector(float dx, float dy, float radius) {
        float len = (float) Math.sqrt(dx * dx + dy * dy);
        if (radius <= 0 || len < radius * 0.18f) return new float[]{0, 0, 0};
        float mag = Math.min(1f, len / radius);
        return new float[]{dx / len * mag, dy / len * mag, mag};
    }

    public static Obstacle hitsObstacle(float x, float z) {
        for (Obstacle o : OBSTACLES) {
            if (Math.abs(x - o.x) < o.hw + PLAYER_R && Math.abs(z - o.z) < o.hd + PLAYER_R) return o;
        }
        return null;
    }

    /** input: x -1..1 (phải+), z -1..1 (xuống+), jump = vừa bấm nhảy. */
    public static void stepPlayer(Player p, float ix, float iz, boolean jump, float dt) {
        if (dt > 0.05f) dt = 0.05f;
        float mag = (float) Math.sqrt(ix * ix + iz * iz);
        if (mag > 1f) { ix /= mag; iz /= mag; mag = 1f; }
        p.moving = mag > 0.01f;
        p.running = p.moving && mag >= RUN_AT;
        float speed = p.running ? RUN : WALK;
        if (p.moving) p.heading = (float) Math.atan2(ix, iz);

        float nx = p.x + ix * speed * dt;
        if (hitsObstacle(nx, p.z) == null) p.x = nx;
        float nz = p.z + iz * speed * dt;
        if (hitsObstacle(p.x, nz) == null) p.z = nz;
        p.x = Math.max(MIN_X, Math.min(MAX_X, p.x));
        p.z = Math.max(MIN_Z, Math.min(MAX_Z, p.z));

        if (jump && p.grounded) { p.vy = JUMP_V; p.grounded = false; }
        if (!p.grounded) {
            p.y += p.vy * dt;
            p.vy += GRAVITY * dt;
            if (p.y <= 0) { p.y = 0; p.vy = 0; p.grounded = true; }
        }
        if (p.punchT > 0) p.punchT = Math.max(0, p.punchT - dt);
        if (p.grabT > 0) p.grabT = Math.max(0, p.grabT - dt);
        if (p.moving && p.grounded) p.animT += dt * (p.running ? 11 : 8);
    }

    public static void startPunch(Player p) { if (p.punchT <= 0 && p.grabT <= 0) p.punchT = PUNCH_TIME; }
    public static void startGrab(Player p)  { if (p.grabT <= 0 && p.punchT <= 0) p.grabT = GRAB_TIME; }
}
