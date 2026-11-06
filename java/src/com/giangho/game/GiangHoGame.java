package com.giangho.game;

import com.badlogic.gdx.ApplicationAdapter;
import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.Input;
import com.badlogic.gdx.InputAdapter;
import com.badlogic.gdx.graphics.Color;
import com.badlogic.gdx.graphics.GL20;
import com.badlogic.gdx.graphics.PerspectiveCamera;
import com.badlogic.gdx.graphics.Pixmap;
import com.badlogic.gdx.graphics.PixmapIO;
import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.VertexAttributes.Usage;
import com.badlogic.gdx.graphics.g2d.BitmapFont;
import com.badlogic.gdx.graphics.g2d.GlyphLayout;
import com.badlogic.gdx.graphics.g2d.SpriteBatch;
import com.badlogic.gdx.graphics.g3d.Environment;
import com.badlogic.gdx.graphics.g3d.Material;
import com.badlogic.gdx.graphics.g3d.Model;
import com.badlogic.gdx.graphics.g3d.ModelBatch;
import com.badlogic.gdx.graphics.g3d.ModelInstance;
import com.badlogic.gdx.graphics.g3d.attributes.BlendingAttribute;
import com.badlogic.gdx.graphics.g3d.attributes.ColorAttribute;
import com.badlogic.gdx.graphics.g3d.attributes.IntAttribute;
import com.badlogic.gdx.graphics.g3d.attributes.TextureAttribute;
import com.badlogic.gdx.graphics.g3d.environment.DirectionalLight;
import com.badlogic.gdx.graphics.g3d.utils.MeshPartBuilder;
import com.badlogic.gdx.graphics.g3d.utils.ModelBuilder;
import com.badlogic.gdx.graphics.glutils.ShapeRenderer;
import com.badlogic.gdx.math.Matrix4;
import com.badlogic.gdx.math.Vector3;
import com.badlogic.gdx.utils.ScreenUtils;

import java.util.ArrayList;
import java.util.List;

/** Giang Hồ Xóm bản Java + LibGDX.
 *  J1.5: hình chibi theo ảnh mẫu của bản gốc — nhân vật đầu to có mặt, nhà mái ngói + hiên sọc,
 *  xe máy, thùng gỗ, chậu cây, vòng chiếm đóng có vương miện. Nút bấm luôn hiện. */
public class GiangHoGame extends ApplicationAdapter {
    public static boolean TOUR = false;

    private PerspectiveCamera cam;
    private ModelBatch batch;
    private Environment env;
    private final List<ModelInstance> worldInstances = new ArrayList<>();
    private final List<ModelInstance> charInstances = new ArrayList<>();
    private final List<Model> models = new ArrayList<>();
    private final List<Texture> textures = new ArrayList<>();

    private World.Player player;
    private Parts me, dummy;
    private final Vector3 camPos = new Vector3(0, 5.2f, 15.5f);

    private SpriteBatch hud;
    private ShapeRenderer shapes;
    private BitmapFont font, fontBig;

    private int joyPointer = -1;
    private float joyX, joyY;
    private boolean jumpQueued;
    private float elapsed;
    private int shotIdx;
    private final float[] shotTimes = {1.0f, 3.1f, 3.88f, 4.85f};

    // ---------- helpers ----------
    private static Color hex(int rgb) {
        return new Color(((rgb >> 16) & 0xff) / 255f, ((rgb >> 8) & 0xff) / 255f, (rgb & 0xff) / 255f, 1f);
    }
    private Material matC(int rgb) { return new Material(ColorAttribute.createDiffuse(hex(rgb))); }
    private Material matTex(String file, boolean transparent) { return matTex(file, transparent, true); }
    private Material matTex(String file, boolean transparent, boolean mipmaps) {
        Texture t = new Texture(Gdx.files.local(file), mipmaps);
        if (mipmaps) t.setFilter(Texture.TextureFilter.MipMapLinearLinear, Texture.TextureFilter.Linear);
        else t.setFilter(Texture.TextureFilter.Linear, Texture.TextureFilter.Linear);
        try { if (mipmaps) t.setAnisotropicFilter(8f); } catch (Exception ignored) {}
        textures.add(t);
        Material m = new Material(TextureAttribute.createDiffuse(t));
        if (transparent) {
            m.set(new BlendingAttribute(GL20.GL_SRC_ALPHA, GL20.GL_ONE_MINUS_SRC_ALPHA));
            m.set(new IntAttribute(IntAttribute.CullFace, 0));
        }
        return m;
    }
    private ModelInstance addTo(List<ModelInstance> list, Model m, float x, float y, float z) {
        models.add(m);
        ModelInstance i = new ModelInstance(m);
        i.transform.setToTranslation(x, y, z);
        list.add(i);
        return i;
    }
    private ModelInstance box(List<ModelInstance> l, float w, float h, float d, Material mat, float x, float y, float z) {
        return addTo(l, new ModelBuilder().createBox(w, h, d, mat, Usage.Position | Usage.Normal | Usage.TextureCoordinates), x, y, z);
    }
    private ModelInstance cyl(List<ModelInstance> l, float r, float h, Material mat, float x, float y, float z) {
        return addTo(l, new ModelBuilder().createCylinder(r * 2, h, r * 2, 14, mat, Usage.Position | Usage.Normal), x, y, z);
    }
    private ModelInstance sphere(List<ModelInstance> l, float r, Material mat, float x, float y, float z) {
        return addTo(l, new ModelBuilder().createSphere(r * 2, r * 2, r * 2, 20, 14, mat, Usage.Position | Usage.Normal), x, y, z);
    }
    private ModelInstance capsule(List<ModelInstance> l, float r, float h, Material mat) {
        Model m = new ModelBuilder().createCapsule(r, h, 12, mat, Usage.Position | Usage.Normal);
        models.add(m);
        ModelInstance i = new ModelInstance(m);
        l.add(i);
        return i;
    }
    private ModelInstance rect(List<ModelInstance> l, float w, float h, Material mat, float x, float y, float z) {
        Model m = new ModelBuilder().createRect(-w / 2, -h / 2, 0, w / 2, -h / 2, 0, w / 2, h / 2, 0, -w / 2, h / 2, 0,
                0, 0, 1, mat, Usage.Position | Usage.Normal | Usage.TextureCoordinates);
        return addTo(l, m, x, y, z);
    }

    /** Mặt phẳng chia lưới nhiều ô nhỏ: tránh lỗi nội suy texture vệt sọc của renderer phần mềm với tam giác lớn. */
    private ModelInstance facadePlane(List<ModelInstance> l, float w, float h, Material mat, float x, float y, float z) {
        int cols = 6, rows = 4;
        ModelBuilder mb = new ModelBuilder();
        mb.begin();
        MeshPartBuilder pb = mb.part("f", GL20.GL_TRIANGLES, Usage.Position | Usage.Normal | Usage.TextureCoordinates, mat);
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                float x0 = -w / 2 + w * c / cols, x1 = -w / 2 + w * (c + 1) / cols;
                float y0 = -h / 2 + h * r / rows, y1 = -h / 2 + h * (r + 1) / rows;
                pb.setUVRange(c / (float) cols, 1 - (r + 1) / (float) rows, (c + 1) / (float) cols, 1 - r / (float) rows);
                pb.rect(x0, y0, 0, x1, y0, 0, x1, y1, 0, x0, y1, 0, 0, 0, 1);
            }
        }
        Model m = mb.end();
        return addTo(l, m, x, y, z);
    }

    @Override
    public void create() {
        cam = new PerspectiveCamera(55, Gdx.graphics.getWidth(), Gdx.graphics.getHeight());
        cam.near = 0.1f; cam.far = 220;
        batch = new ModelBatch();
        env = new Environment();
        env.set(new ColorAttribute(ColorAttribute.AmbientLight, 0.8f, 0.79f, 0.76f, 1f));
        env.add(new DirectionalLight().set(1f, 0.95f, 0.85f, -0.45f, -0.8f, -0.35f));

        buildStreet();
        player = World.createPlayer("Tín Xóm", 0, 6);
        me = buildCharacter(0xf0681a, "assets/face.png", false);
        dummy = buildCharacter(0x1f8a70, "assets/face2.png", true);
        pose(dummy, -1.6f, 0, -0.8f, 2.7f, 0, false, true, 0, 0);

        hud = new SpriteBatch();
        shapes = new ShapeRenderer();
        font = loadFont(26);
        fontBig = loadFont(34);
        Gdx.input.setInputProcessor(new InputAdapter() {
            @Override public boolean touchDown(int sx, int sy, int pointer, int button) { onTouch(sx, sy, pointer, true); return true; }
            @Override public boolean touchDragged(int sx, int sy, int pointer) { onTouch(sx, sy, pointer, false); return true; }
            @Override public boolean touchUp(int sx, int sy, int pointer, int button) {
                if (pointer == joyPointer) { joyPointer = -1; joyX = 0; joyY = 0; }
                return true;
            }
        });
    }

    private BitmapFont loadFont(int size) {
        try {
            com.badlogic.gdx.graphics.g2d.freetype.FreeTypeFontGenerator gen =
                new com.badlogic.gdx.graphics.g2d.freetype.FreeTypeFontGenerator(Gdx.files.local("assets/font.ttf"));
            com.badlogic.gdx.graphics.g2d.freetype.FreeTypeFontGenerator.FreeTypeFontParameter p =
                new com.badlogic.gdx.graphics.g2d.freetype.FreeTypeFontGenerator.FreeTypeFontParameter();
            p.size = size;
            p.characters = com.badlogic.gdx.graphics.g2d.freetype.FreeTypeFontGenerator.DEFAULT_CHARS +
                "àáâãèéêìíòóôõùúýăđơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ" +
                "ÀÁÂÃÈÉÊÌÍÒÓÔÕÙÚÝĂĐƠƯẠẢẤẦẨẪẬẮẰẲẴẶẸẺẼẾỀỂỄỆỈỊỌỎỐỒỔỖỘỚỜỞỠỢỤỦỨỪỬỮỰỲỴỶỸ·";
            BitmapFont f = gen.generateFont(p);
            gen.dispose();
            return f;
        } catch (Exception e) {
            return new BitmapFont();
        }
    }

    // ---------- Thế giới ----------
    private void buildStreet() {
        List<ModelInstance> l = worldInstances;
        box(l, 120, 0.1f, 90, matC(0x9aa0a3), 0, -0.05f, 0);
        box(l, 92, 0.1f, 30, matC(0x55575c), 0, 0.04f, 0);
        box(l, 26, 0.1f, 18, matC(0xcbb894), 0, 0.1f, 0);
        for (int i = -5; i <= 5; i++) box(l, 4, 0.05f, 0.5f, matC(0xf5d76e), i * 8, 0.17f, 0);

        int idx = 0;
        for (World.Obstacle o : World.OBSTACLES) {
            boolean stall = o.h < 3;
            float face = o.z < 0 ? 1 : -1;
            box(l, o.hw * 2, o.h, o.hd * 2, matC(o.color), o.x, o.h / 2, o.z);
            if (stall) {
                box(l, o.hw * 2 + 1, 0.22f, o.hd * 2 + 1, matC(0xc96f4a), o.x, o.h + 0.45f, o.z);
                continue;
            }
            // mặt tiền vẽ AI (J1.6): nguyên tấm texture có sẵn mái ngói/hiên/cửa/bảng hiệu
            facadePlane(l, o.hw * 2 + 0.4f, o.h, matTex("assets/facades/f" + idx + ".png", false, false), o.x, o.h / 2, o.z + face * (o.hd + 0.07f))
                    .transform.rotate(Vector3.Y, face < 0 ? 180 : 0);
            box(l, o.hw * 2 + 0.7f, 0.4f, o.hd * 2 + 0.7f, matC(0xb85c38), o.x, o.h + 0.16f, o.z); // nắp mái
            idx++;
        }

        // vòng chiếm đóng giữa phố + cờ vương miện
        Material discMat = new Material(ColorAttribute.createDiffuse(new Color(0.08f, 0.5f, 0.47f, 0.55f)));
        discMat.set(new BlendingAttribute(GL20.GL_SRC_ALPHA, GL20.GL_ONE_MINUS_SRC_ALPHA));
        cyl(l, 4.3f, 0.05f, discMat, 0, 0.19f, 0);
        Model crownM = new ModelBuilder().createRect(-2.1f, 0, 2.1f, 2.1f, 0, 2.1f, 2.1f, 0, -2.1f, -2.1f, 0, -2.1f,
                0, 1, 0, matTex("assets/crown.png", true), Usage.Position | Usage.Normal | Usage.TextureCoordinates);
        addTo(l, crownM, 0, 0.23f, 0);
        cyl(l, 0.07f, 3.6f, matC(0x6d4c41), 4.9f, 1.8f, 0.8f);
        rect(l, 1.7f, 1.05f, matTex("assets/flag.png", false), 5.78f, 3.05f, 0.8f);

        // xe máy + thùng gỗ (góc phố nam)
        buildScooter(20.5f, 13.6f, -0.5f);
        box(l, 0.95f, 0.95f, 0.95f, matC(0xb08954), 23.6f, 0.48f, 14.6f).transform.rotate(Vector3.Y, 18);
        box(l, 0.95f, 0.95f, 0.95f, matC(0xbd975f), 23.5f, 1.43f, 14.7f).transform.rotate(Vector3.Y, -8);
        box(l, 0.95f, 0.95f, 0.95f, matC(0xa87f4e), 24.7f, 0.48f, 14.4f).transform.rotate(Vector3.Y, 40);

        // cột đèn + cây
        for (int x = -30; x <= 30; x += 12) {
            for (float z : new float[]{-14.5f, 14.5f}) {
                cyl(l, 0.12f, 4.6f, matC(0x37474f), x, 2.3f, z);
                sphere(l, 0.42f, matC(0xffe9a3), x, 4.8f, z);
            }
        }
        for (int x = -33; x <= 33; x += 11) {
            for (float z : new float[]{-15.4f, 15.4f}) {
                cyl(l, 0.3f, 1.8f, matC(0x6d4c41), x, 0.9f, z);
                sphere(l, 1.6f, matC(0x3e7d3a), x, 3.2f, z);
            }
        }
    }

    private void buildScooter(float x, float z, float ry) {
        List<ModelInstance> l = worldInstances;
        Matrix4 base = new Matrix4().setToTranslation(x, 0, z).rotate(Vector3.Y, ry * 57.2958f);
        ModelBuilder mb = new ModelBuilder();
        Object[][] parts = {
            {mb.createBox(0.52f, 0.42f, 1.5f, matC(0x3f8f83), Usage.Position | Usage.Normal), new Vector3(0, 0.55f, 0.1f)},
            {mb.createBox(0.5f, 0.85f, 0.28f, matC(0x49a294), Usage.Position | Usage.Normal), new Vector3(0, 0.85f, 0.82f)},
            {mb.createBox(0.46f, 0.16f, 0.85f, matC(0x2b2b2b), Usage.Position | Usage.Normal), new Vector3(0, 0.95f, -0.25f)},
            {mb.createBox(0.6f, 0.08f, 0.08f, matC(0x37474f), Usage.Position | Usage.Normal), new Vector3(0, 1.38f, 0.85f)},
        };
        for (Object[] part : parts) {
            Model m = (Model) part[0];
            models.add(m);
            ModelInstance i = new ModelInstance(m);
            Vector3 off = (Vector3) part[1];
            i.transform.set(base).mul(new Matrix4().setToTranslation(off.x, off.y, off.z));
            l.add(i);
        }
        Model wheel = mb.createCylinder(0.68f, 0.12f, 0.68f, 16, matC(0x222222), Usage.Position | Usage.Normal);
        models.add(wheel);
        for (float wz : new float[]{0.85f, -0.72f}) {
            ModelInstance wi = new ModelInstance(wheel);
            wi.transform.set(base).mul(new Matrix4().setToTranslation(0, 0.34f, wz).rotate(Vector3.Z, 90));
            l.add(wi);
        }
    }

    // ---------- Nhân vật chibi ----------
    private static class Parts {
        ModelInstance legL, legR, shoeL, shoeR, body, armL, armR, head, hair, hairBack, face;
        List<ModelInstance> all = new ArrayList<>();
    }

    private Parts buildCharacter(int shirtColor, String faceFile, boolean longHair) {
        Parts p = new Parts();
        List<ModelInstance> l = p.all;
        Material skin = matC(0xf2c094), shirt = matC(shirtColor), pants = matC(0x33393f), hairM = matC(0x2a2320);
        p.legL = capsule(l, 0.14f, 0.30f, pants);
        p.legR = capsule(l, 0.14f, 0.30f, pants);
        p.shoeL = box(l, 0.3f, 0.15f, 0.48f, matC(0xf5f2ea), 0, 0, 0);
        p.shoeR = box(l, 0.3f, 0.15f, 0.48f, matC(0xf5f2ea), 0, 0, 0);
        p.body = capsule(l, 0.37f, 0.78f, shirt);
        p.armL = capsule(l, 0.13f, 0.40f, skin);
        p.armR = capsule(l, 0.13f, 0.40f, skin);
        p.head = sphere(l, 0.44f, skin, 0, 0, 0);
        p.hair = sphere(l, 0.465f, hairM, 0, 0, 0);
        if (longHair) p.hairBack = box(l, 0.78f, 0.85f, 0.3f, hairM, 0, 0, 0);
        p.face = rect(l, 0.64f, 0.54f, matTex(faceFile, true), 0, 0, 0);
        charInstances.addAll(l);
        return p;
    }

    private final Matrix4 tmpL = new Matrix4();
    private void setPart(ModelInstance inst, Matrix4 group, float lx, float ly, float lz, float rotXDeg, float drop) {
        tmpL.setToTranslation(lx, ly, lz);
        if (rotXDeg != 0) tmpL.rotate(Vector3.X, rotXDeg);
        tmpL.translate(0, -drop, 0);
        inst.transform.set(group).mul(tmpL);
    }

    private void pose(Parts p, float x, float y, float z, float heading, float animT,
                      boolean moving, boolean grounded, float punchT, float grabT) {
        Matrix4 group = new Matrix4().setToTranslation(x, y, z).rotate(Vector3.Y, heading * 57.2958f);
        float swing = (moving && grounded) ? (float) Math.sin(animT) * 40f : 0;
        float legL = swing, legR = -swing;
        if (!grounded) { legL = 22; legR = -16; }
        setPart(p.legL, group, -0.17f, 0.55f, 0, legL, 0.22f);
        setPart(p.legR, group, 0.17f, 0.55f, 0, legR, 0.22f);
        setPart(p.shoeL, group, -0.17f, 0.55f, 0.05f, legL, 0.47f);
        setPart(p.shoeR, group, 0.17f, 0.55f, 0.05f, legR, 0.47f);
        setPart(p.body, group, 0, 0.98f, 0, 0, 0);
        float armLS = -swing, armRS = swing;
        if (punchT > 0) { float t = 1 - punchT / World.PUNCH_TIME; armRS = (float) -Math.sin(t * Math.PI) * 100f; }
        if (grabT > 0) { float t = 1 - grabT / World.GRAB_TIME; armLS = armRS = (float) -Math.sin(t * Math.PI) * 80f; }
        setPart(p.armL, group, -0.47f, 1.34f, 0, armLS, 0.24f);
        setPart(p.armR, group, 0.47f, 1.34f, 0, armRS, 0.24f);
        setPart(p.head, group, 0, 1.8f, 0, 0, 0);
        tmpL.setToTranslation(0, 1.94f, -0.06f).scale(1f, 0.72f, 1f);
        p.hair.transform.set(group).mul(tmpL);
        if (p.hairBack != null) setPart(p.hairBack, group, 0, 1.55f, -0.36f, 0, 0);
        setPart(p.face, group, 0, 1.76f, 0.425f, 0, 0);
    }

    // ---------- Đầu vào ----------
    private float unit() { return Gdx.graphics.getHeight() / 480f; }
    private float joyCx() { return 96 * unit(); }
    private float joyCy() { return 96 * unit(); }
    private float joyR() { return 62 * unit(); }

    private boolean hit(float x, float y, float cx, float cy, float r) {
        float dx = x - cx, dy = y - cy;
        return dx * dx + dy * dy <= r * r;
    }
    private void updateJoy(float gx, float gy) {
        float[] v = World.joystickVector(gx - joyCx(), -(gy - joyCy()), joyR());
        joyX = v[0]; joyY = v[1];
    }
    private void onTouch(int sx, int sy, int pointer, boolean down) {
        float h = Gdx.graphics.getHeight();
        float gx = sx, gy = h - sy;
        float u = unit();
        if (down) {
            if (hit(gx, gy, Gdx.graphics.getWidth() - 66 * u, 66 * u, 44 * u)) { World.startPunch(player); return; }
            if (hit(gx, gy, Gdx.graphics.getWidth() - 152 * u, 44 * u, 33 * u)) { jumpQueued = true; return; }
            if (hit(gx, gy, Gdx.graphics.getWidth() - 112 * u, 122 * u, 33 * u)) { World.startGrab(player); return; }
            if (hit(gx, gy, joyCx(), joyCy(), joyR() + 14 * u)) { joyPointer = pointer; updateJoy(gx, gy); }
        } else if (pointer == joyPointer) updateJoy(gx, gy);
    }

    private float[] readInput() {
        float x = joyX, z = joyY;
        if (TOUR) {
            float t = elapsed;
            if (t < 1.2f) { x = 0; z = 0; }
            else if (t < 3.2f) { x = -0.05f; z = -0.5f; }
            else if (t < 4.2f) { x = 0; z = 0; if (Math.abs(t - 3.7f) < 0.02f) World.startPunch(player); }
            else { x = 0; z = 0; if (Math.abs(t - 4.45f) < 0.02f) jumpQueued = true; }
        } else {
            if (Gdx.input.isKeyPressed(Input.Keys.A) || Gdx.input.isKeyPressed(Input.Keys.LEFT)) x -= 1;
            if (Gdx.input.isKeyPressed(Input.Keys.D) || Gdx.input.isKeyPressed(Input.Keys.RIGHT)) x += 1;
            if (Gdx.input.isKeyPressed(Input.Keys.W) || Gdx.input.isKeyPressed(Input.Keys.UP)) z -= 1;
            if (Gdx.input.isKeyPressed(Input.Keys.S) || Gdx.input.isKeyPressed(Input.Keys.DOWN)) z += 1;
            if (Gdx.input.isKeyJustPressed(Input.Keys.SPACE) || Gdx.input.isKeyJustPressed(Input.Keys.K)) jumpQueued = true;
            if (Gdx.input.isKeyJustPressed(Input.Keys.J)) World.startPunch(player);
            if (Gdx.input.isKeyJustPressed(Input.Keys.L)) World.startGrab(player);
        }
        boolean j = jumpQueued; jumpQueued = false;
        return new float[]{x, z, j ? 1 : 0};
    }

    @Override
    public void render() {
        float dt = Math.min(0.05f, Gdx.graphics.getDeltaTime());
        elapsed += dt;
        float[] in = readInput();
        World.stepPlayer(player, in[0], in[1], in[2] > 0, dt);
        pose(me, player.x, player.y, player.z, player.heading, player.animT,
                player.moving, player.grounded, player.punchT, player.grabT);

        Gdx.gl.glViewport(0, 0, Gdx.graphics.getWidth(), Gdx.graphics.getHeight());
        Gdx.gl.glClearColor(0.55f, 0.74f, 0.88f, 1);
        Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT | GL20.GL_DEPTH_BUFFER_BIT);

        Vector3 target = new Vector3(player.x, player.y + 5.2f, player.z + 9.5f);
        camPos.lerp(target, 0.08f);
        cam.position.set(camPos);
        cam.lookAt(player.x, player.y + 1.1f, player.z - 1);
        cam.up.set(Vector3.Y);
        cam.update();

        batch.begin(cam);
        for (ModelInstance i : worldInstances) batch.render(i, env);
        for (ModelInstance i : charInstances) batch.render(i, env);
        batch.end();

        drawHud();

        if (TOUR && shotIdx < shotTimes.length && elapsed >= shotTimes[shotIdx]) {
            saveShot("shots/java-tour" + (shotIdx + 1) + ".png");
            shotIdx++;
            if (shotIdx >= shotTimes.length) Gdx.app.exit();
        }
    }

    private void saveShot(String path) {
        int w = Gdx.graphics.getWidth(), h = Gdx.graphics.getHeight();
        byte[] pixels = ScreenUtils.getFrameBufferPixels(0, 0, w, h, true);
        Pixmap pm = new Pixmap(w, h, Pixmap.Format.RGBA8888);
        pm.getPixels().put(pixels).flip();
        PixmapIO.writePNG(Gdx.files.local(path), pm);
        pm.dispose();
        Gdx.app.log("GHX", "saved " + path);
    }

    private void drawHud() {
        int w = Gdx.graphics.getWidth(), h = Gdx.graphics.getHeight();
        float u = unit();
        shapes.begin(ShapeRenderer.ShapeType.Filled);
        shapes.setColor(0.05f, 0.12f, 0.19f, 0.78f);
        shapes.rect(10, h - 44 * u, 300 * u, 34 * u);
        shapes.setColor(0.05f, 0.12f, 0.19f, 0.38f);
        shapes.circle(joyCx(), joyCy(), joyR());
        shapes.setColor(1f, 0.85f, 0.54f, 0.92f);
        shapes.circle(joyCx() + joyX * joyR() * 0.62f, joyCy() - joyY * joyR() * 0.62f, 27 * u);
        shapes.setColor(0.91f, 0.36f, 0.05f, 0.95f);
        shapes.circle(w - 66 * u, 66 * u, 44 * u);
        shapes.setColor(0.08f, 0.17f, 0.26f, 0.85f);
        shapes.circle(w - 152 * u, 44 * u, 33 * u);
        shapes.circle(w - 112 * u, 122 * u, 33 * u);
        shapes.end();

        hud.begin();
        font.setColor(Color.WHITE);
        font.draw(hud, "Chợ Mới 01 · Chiếm phố — Tín Xóm", 22, h - 16 * u);
        fontBig.setColor(Color.WHITE);
        centerText("ĐẤM", w - 66 * u, 66 * u + 11);
        centerText("NHẢY", w - 152 * u, 44 * u + 9);
        centerText("TÚM", w - 112 * u, 122 * u + 9);
        drawName(player.name, player.x, player.y + 2.55f, player.z);
        drawName("Gà Con", -1.6f, 2.55f, -0.8f);
        hud.end();
    }

    private void drawName(String name, float x, float y, float z) {
        Vector3 v = new Vector3(x, y, z).prj(cam.combined);
        if (v.z >= 1) return;
        float sx = (v.x * 0.5f + 0.5f) * Gdx.graphics.getWidth();
        float sy = (v.y * 0.5f + 0.5f) * Gdx.graphics.getHeight();
        GlyphLayout gl = new GlyphLayout(font, name);
        font.draw(hud, name, sx - gl.width / 2, sy);
    }

    private void centerText(String text, float cx, float cy) {
        GlyphLayout gl = new GlyphLayout(fontBig, text);
        fontBig.draw(hud, text, cx - gl.width / 2, cy);
    }

    @Override
    public void dispose() {
        batch.dispose();
        for (Model m : models) m.dispose();
        for (Texture t : textures) t.dispose();
        hud.dispose(); shapes.dispose(); font.dispose(); fontBig.dispose();
    }
}
