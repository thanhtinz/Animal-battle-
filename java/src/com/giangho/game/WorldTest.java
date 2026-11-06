package com.giangho.game;

/** Test logic World bằng main() thường (không cần JUnit) — port từ tests/test_step2.js.
 *  Chạy: java -cp build com.giangho.game.WorldTest */
public class WorldTest {
    static int pass = 0;
    static void ok(String name, boolean cond) {
        if (!cond) throw new AssertionError("FAIL: " + name);
        pass++; System.out.println("PASS " + name);
    }
    static final float DT = 1f / 60;
    static void run(World.Player p, float x, float z, float seconds) {
        int n = Math.round(seconds / DT);
        for (int i = 0; i < n; i++) World.stepPlayer(p, x, z, false, DT);
    }

    public static void main(String[] args) {
        // joystick
        ok("joystick vùng chết = 0", World.joystickVector(3, 2, 56)[2] == 0);
        float[] v = World.joystickVector(100, 0, 56);
        ok("joystick hết cỡ mag=1", Math.abs(v[2] - 1) < 1e-6 && v[0] > 0.99f);
        v = World.joystickVector(0, 28, 56);
        ok("joystick nửa mag~0.5", Math.abs(v[2] - 0.5f) < 1e-6);

        // di chuyển
        World.Player p = World.createPlayer("A", 0, 0);
        run(p, 0, 0, 1); ok("đứng yên khi không input", p.x == 0);
        p = World.createPlayer("A", 0, 0); run(p, 0.5f, 0, 1);
        ok("đi bộ nửa cần ~ nửa WALK", Math.abs(p.x - World.WALK * 0.5f) < 0.2f && !p.running);
        p = World.createPlayer("A", 0, 0); run(p, 1, 0, 0.5f);
        ok("hết cỡ thì chạy", p.running);
        World.Player a = World.createPlayer("A", 0, 0); run(a, 1, 0, 1);
        World.Player b = World.createPlayer("B", 0, 0); run(b, 1, 1, 1);
        double da = Math.hypot(a.x, a.z), db = Math.hypot(b.x, b.z);
        ok("chéo không nhanh hơn thẳng", Math.abs(da - db) < 0.25);
        p = World.createPlayer("A", 0, 0); run(p, 1, 0, 0.1f);
        ok("quay mặt theo hướng đi", Math.abs(p.heading - Math.PI / 2) < 1e-5);

        // biên + va chạm
        p = World.createPlayer("A", 0, 0); run(p, -1, 0, 20);
        ok("không ra ngoài biên", p.x >= World.MIN_X);
        World.Obstacle house = World.OBSTACLES[0];
        p = World.createPlayer("A", house.x, 0); run(p, 0, -1, 10);
        ok("nhà chặn trước tường", p.z > house.z + house.hd && Math.abs(p.z - (house.z + house.hd + World.PLAYER_R)) < 0.6f);
        ok("hitsObstacle giữa phố trống", World.hitsObstacle(0, 0) == null);
        ok("hitsObstacle trong nhà", World.hitsObstacle(World.OBSTACLES[2].x, World.OBSTACLES[2].z) != null);

        // nhảy
        p = World.createPlayer("A", 0, 0);
        World.stepPlayer(p, 0, 0, true, DT);
        ok("nhảy rời đất", !p.grounded && p.vy > 0);
        float maxY = 0;
        for (int i = 0; i < 120; i++) { World.stepPlayer(p, 0, 0, false, DT); maxY = Math.max(maxY, p.y); }
        ok("nhảy cao > 1 rồi chạm đất", maxY > 1 && p.grounded && p.y == 0);

        // đấm/túm
        p = World.createPlayer("A", 0, 0); World.startPunch(p);
        ok("đấm bật timer", p.punchT > 0);
        float t = p.punchT; World.startPunch(p);
        ok("không đấm chồng", p.punchT == t);
        World.startGrab(p);
        ok("túm không chạy cùng đấm", p.grabT == 0);
        run(p, 0, 0, 1);
        ok("đấm tự hết", p.punchT == 0);

        // dữ liệu map khớp bản JS
        ok("12 vật cản như bản JS", World.OBSTACLES.length == 12);
        ok("10 nhà có biển hiệu", java.util.Arrays.stream(World.OBSTACLES).filter(o -> o.h >= 3).count() == 10);

        System.out.println("\nJava WorldTest: " + pass + "/" + pass + " PASS");
    }
}
