package com.giangho.game;

import com.badlogic.gdx.ApplicationAdapter;
import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.Input;
import com.badlogic.gdx.InputAdapter;
import com.badlogic.gdx.files.FileHandle;
import com.badlogic.gdx.graphics.Color;
import com.badlogic.gdx.graphics.GL20;
import com.badlogic.gdx.graphics.PerspectiveCamera;
import com.badlogic.gdx.graphics.Pixmap;
import com.badlogic.gdx.graphics.PixmapIO;
import com.badlogic.gdx.graphics.Texture;
import com.badlogic.gdx.graphics.VertexAttributes.Usage;
import com.badlogic.gdx.graphics.g2d.BitmapFont;
import com.badlogic.gdx.graphics.g2d.SpriteBatch;
import com.badlogic.gdx.graphics.g3d.Environment;
import com.badlogic.gdx.graphics.g3d.Material;
import com.badlogic.gdx.graphics.g3d.Model;
import com.badlogic.gdx.graphics.g3d.ModelBatch;
import com.badlogic.gdx.graphics.g3d.ModelInstance;
import com.badlogic.gdx.graphics.g3d.attributes.ColorAttribute;
import com.badlogic.gdx.graphics.g3d.environment.DirectionalLight;
import com.badlogic.gdx.graphics.g3d.utils.ModelBuilder;
import com.badlogic.gdx.graphics.glutils.ShapeRenderer;
import com.badlogic.gdx.math.Matrix4;
import com.badlogic.gdx.math.Vector3;
import com.badlogic.gdx.utils.ScreenUtils;

import java.util.ArrayList;
import java.util.List;

/** Giang Hồ Xóm bản Java + LibGDX — J1: hình 3D khu phố + nhân vật + joystick/nút bấm luôn hiện.
 *  Camera bám sau nhân vật (góc cố định, xoay/zoom ở bước sau). Đấm/Túm mới có hoạt hình tay. */
public class GiangHoGame extends ApplicationAdapter {
    public static boolean TOUR = false;

    private PerspectiveCamera cam;
    private ModelBatch batch;
    private Environment env;
    private final List<ModelInstance> worldInstances = new ArrayList<>();
    private final List<Model> models = new ArrayList<>();
    private final List<Texture> textures = new ArrayList<>();

    private World.Player player;
    private ModelInstance bodyI, headI, hairI, legLI, legRI, armLI, armRI;
    private final Vector3 camPos = new Vector3(0, 8.5f, 23.5f);

    private SpriteBatch hud;
    private ShapeRenderer shapes;
    private BitmapFont font, fontBig;

    // Đầu vào
    private int joyPointer = -1;
    private float joyX, joyY;
    private boolean jumpQueued;
    private float elapsed;
    private int shotIdx;
    private final float[] shotTimes = {1.0f, 3.0f, 4.05f, 4.85f};

    private ModelInstance box(float w, float h, float d, Color c, float x, float y, float z) {
        ModelBuilder mb = new ModelBuilder();
        Model m = mb.createBox(w, h, d, new Material(ColorAttribute.createDiffuse(c)),
                Usage.Position | Usage.Normal);
        models.add(m);
        ModelInstance i = new ModelInstance(m);
        i.transform.setToTranslation(x, y, z);
        worldInstances.add(i);
        return i;
    }

    private ModelInstance cyl(float rTop, float rBot, float h, Color c, float x, float y, float z) {
        ModelBuilder mb = new ModelBuilder();
        Model m = mb.createCylinder(rTop * 2, h, rBot * 2, 12, new Material(ColorAttribute.createDiffuse(c)),
                Usage.Position | Usage.Normal);
        models.add(m);
        ModelInstance i = new ModelInstance(m);
        i.transform.setToTranslation(x, y, z);
        worldInstances.add(i);
        return i;
    }

    private ModelInstance sphere(float r, Color c, float x, float y, float z) {
        ModelBuilder mb = new ModelBuilder();
        Model m = mb.createSphere(r * 2, r * 2, r * 2, 14, 10, new Material(ColorAttribute.createDiffuse(c)),
                Usage.Position | Usage.Normal);
        models.add(m);
        ModelInstance i = new ModelInstance(m);
        i.transform.setToTranslation(x, y, z);
        worldInstances.add(i);
        return i;
    }

    private static Color hex(int rgb) {
        return new Color(((rgb >> 16) & 0xff) / 255f, ((rgb >> 8) & 0xff) / 255f, (rgb & 0xff) / 255f, 1f);
    }

    @Override
    public void create() {
        cam = new PerspectiveCamera(55, Gdx.graphics.getWidth(), Gdx.graphics.getHeight());
        cam.near = 0.1f; cam.far = 220;
        batch = new ModelBatch();
        env = new Environment();
        env.set(new ColorAttribute(ColorAttribute.AmbientLight, 0.75f, 0.75f, 0.78f, 1f));
        env.add(new DirectionalLight().set(0.95f, 0.9f, 0.8f, -0.45f, -0.8f, -0.35f));

        buildStreet();
        buildCharacter();
        player = World.createPlayer("Tín Xóm", 0, 10);

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

    private void buildStreet() {
        box(120, 0.1f, 90, hex(0x8a8d90), 0, -0.05f, 0);            // nền (mặt trên y=0)
        box(92, 0.1f, 30, hex(0x4a4d52), 0, 0.04f, 0);              // đường nhựa (mặt trên y=0.09)
        box(26, 0.1f, 18, hex(0xb8a888), 0, 0.1f, 0);               // sân giữa (mặt trên y=0.15)
        for (int i = -5; i <= 5; i++) box(4, 0.05f, 0.5f, hex(0xf5d76e), i * 8, 0.17f, 0); // vạch đường

        int idx = 0;
        for (World.Obstacle o : World.OBSTACLES) {
            boolean stall = o.h < 3;
            box(o.hw * 2, o.h, o.hd * 2, hex(o.color), o.x, o.h / 2, o.z);
            if (stall) {
                box(o.hw * 2 + 1, 0.25f, o.hd * 2 + 1, hex(0xd8542e), o.x, o.h + 0.5f, o.z);
            } else {
                box(o.hw * 2 + 0.6f, 0.4f, o.hd * 2 + 0.6f, hex(0x2c2f36), o.x, o.h + 0.2f, o.z);
                // biển hiệu: mặt phẳng (rect) có texture chữ — dùng rect thay box để UV trải đúng 1 mặt
                Texture t = new Texture(Gdx.files.local("assets/signs/sign" + idx + ".png"));
                t.setFilter(Texture.TextureFilter.Linear, Texture.TextureFilter.Linear);
                textures.add(t);
                ModelBuilder mb = new ModelBuilder();
                Model m = mb.createRect(-3.75f, -0.95f, 0, 3.75f, -0.95f, 0, 3.75f, 0.95f, 0, -3.75f, 0.95f, 0,
                        0, 0, 1,
                        new Material(new com.badlogic.gdx.graphics.g3d.attributes.TextureAttribute(
                                com.badlogic.gdx.graphics.g3d.attributes.TextureAttribute.Diffuse, t)),
                        Usage.Position | Usage.Normal | Usage.TextureCoordinates);
                models.add(m);
                ModelInstance s = new ModelInstance(m);
                float face = o.z < 0 ? 1 : -1;
                s.transform.setToTranslation(o.x, o.h - 1.6f, o.z + face * (o.hd + 0.1f));
                if (face < 0) s.transform.rotate(Vector3.Y, 180);
                worldInstances.add(s);
                box(o.hw * 2, 0.18f, 2.2f, hex(0xd8542e), o.x, o.h - 3.1f, o.z + face * (o.hd + 1));
                idx++;
            }
        }
        for (int x = -30; x <= 30; x += 12) {
            for (float z : new float[]{-14.5f, 14.5f}) {
                cyl(0.12f, 0.12f, 4.6f, hex(0x37474f), x, 2.3f, z);
                sphere(0.42f, hex(0xffe9a3), x, 4.8f, z);
            }
        }
        for (int x = -33; x <= 33; x += 11) {
            for (float z : new float[]{-15.4f, 15.4f}) {
                cyl(0.3f, 0.36f, 1.8f, hex(0x6d4c41), x, 0.9f, z);
                sphere(1.6f, hex(0x3e7d3a), x, 3.2f, z);
            }
        }
    }

    private ModelInstance part(float w, float h, float d, Color c) {
        ModelBuilder mb = new ModelBuilder();
        Model m = mb.createBox(w, h, d, new Material(ColorAttribute.createDiffuse(c)),
                Usage.Position | Usage.Normal);
        models.add(m);
        return new ModelInstance(m);
    }

    private void buildCharacter() {
        Color skin = hex(0xf0b98a), shirt = hex(0xf0681a), pants = hex(0x263238), hair = hex(0x212121);
        legLI = part(0.34f, 0.85f, 0.38f, pants);
        legRI = part(0.34f, 0.85f, 0.38f, pants);
        bodyI = part(0.95f, 1.0f, 0.55f, shirt);
        armLI = part(0.3f, 0.9f, 0.34f, shirt);
        armRI = part(0.3f, 0.9f, 0.34f, shirt);
        headI = part(0.62f, 0.62f, 0.6f, skin);
        hairI = part(0.68f, 0.2f, 0.66f, hair);
    }

    // ---- Đầu vào ----
    private float unit() { return Gdx.graphics.getHeight() / 480f; }
    private float joyCx() { return 96 * unit(); }
    private float joyCy() { return 96 * unit(); }
    private float joyR() { return 62 * unit(); }

    private void onTouch(int sx, int sy, int pointer, boolean down) {
        float h = Gdx.graphics.getHeight();
        float gx = sx, gy = h - sy; // về hệ y-từ-dưới
        float u = unit();
        if (down) {
            // nút bấm bên phải
            if (hit(gx, gy, Gdx.graphics.getWidth() - 66 * u, 66 * u, 44 * u)) { World.startPunch(player); return; }
            if (hit(gx, gy, Gdx.graphics.getWidth() - 152 * u, 44 * u, 33 * u)) { jumpQueued = true; return; }
            if (hit(gx, gy, Gdx.graphics.getWidth() - 112 * u, 122 * u, 33 * u)) { World.startGrab(player); return; }
            if (hit(gx, gy, joyCx(), joyCy(), joyR() + 14 * u)) { joyPointer = pointer; updateJoy(gx, gy); }
        } else if (pointer == joyPointer) {
            updateJoy(gx, gy);
        }
    }

    private boolean hit(float x, float y, float cx, float cy, float r) {
        float dx = x - cx, dy = y - cy;
        return dx * dx + dy * dy <= r * r;
    }

    private void updateJoy(float gx, float gy) {
        float[] v = World.joystickVector(gx - joyCx(), -(gy - joyCy()), joyR());
        joyX = v[0]; joyY = v[1];
    }

    private float[] readInput() {
        float x = joyX, z = joyY;
        if (TOUR) {
            float t = elapsed;
            if (t < 1.2f) { x = 0; z = 0; }
            else if (t < 3.2f) { x = 0; z = -1; }
            else if (t < 4.2f) { x = 0.8f; z = -0.4f; if (Math.abs(t - 3.6f) < 0.02f) World.startPunch(player); }
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

    private final Matrix4 tmpL = new Matrix4();
    /** Đặt một bộ phận: dịch tới điểm neo (khớp), xoay quanh khớp theo trục X (độ), rồi mới thả xuống theo chiều dài. */
    private void setPart(ModelInstance inst, Matrix4 group, float lx, float ly, float lz, float rotXDeg, float pivotDrop) {
        tmpL.setToTranslation(lx, ly, lz);
        if (rotXDeg != 0) tmpL.rotate(Vector3.X, rotXDeg);
        tmpL.translate(0, -pivotDrop, 0);
        inst.transform.set(group).mul(tmpL);
    }

    @Override
    public void render() {
        float dt = Math.min(0.05f, Gdx.graphics.getDeltaTime());
        elapsed += dt;
        float[] in = readInput();
        World.stepPlayer(player, in[0], in[1], in[2] > 0, dt);

        Gdx.gl.glViewport(0, 0, Gdx.graphics.getWidth(), Gdx.graphics.getHeight());
        Gdx.gl.glClearColor(0.53f, 0.71f, 0.85f, 1);
        Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT | GL20.GL_DEPTH_BUFFER_BIT);

        // Camera bám sau nhân vật
        Vector3 target = new Vector3(player.x, player.y + 8.5f, player.z + 13.5f);
        camPos.lerp(target, 0.08f);
        cam.position.set(camPos);
        cam.lookAt(player.x, player.y + 1.2f, player.z - 2);
        cam.up.set(Vector3.Y);
        cam.update();

        // Ma trận nhóm nhân vật
        Matrix4 group = new Matrix4().setToTranslation(player.x, player.y, player.z)
                .rotate(Vector3.Y, player.heading * 57.2958f);
        float swing = (player.moving && player.grounded) ? (float) Math.sin(player.animT) * 37f : 0;
        float legL = swing, legR = -swing;
        if (!player.grounded) { legL = 20; legR = -14; }
        setPart(legLI, group, -0.22f, 0.95f, 0, legL, 0.45f);
        setPart(legRI, group, 0.22f, 0.95f, 0, legR, 0.45f);
        setPart(bodyI, group, 0, 1.32f, 0, 0, 0);
        float armLS = -swing, armRS = swing;
        if (player.punchT > 0) {
            float p = 1 - player.punchT / World.PUNCH_TIME;
            armRS = (float) -Math.sin(p * Math.PI) * 97f;
        }
        if (player.grabT > 0) {
            float q = 1 - player.grabT / World.GRAB_TIME;
            armLS = armRS = (float) -Math.sin(q * Math.PI) * 77f;
        }
        setPart(armLI, group, -0.66f, 1.8f, 0, armLS, 0.35f);
        setPart(armRI, group, 0.66f, 1.8f, 0, armRS, 0.35f);
        setPart(headI, group, 0, 2.18f, 0, 0, 0);
        setPart(hairI, group, 0, 2.55f, 0, 0, 0);

        batch.begin(cam);
        for (ModelInstance i : worldInstances) batch.render(i, env);
        batch.render(bodyI, env); batch.render(headI, env); batch.render(hairI, env);
        batch.render(legLI, env); batch.render(legRI, env);
        batch.render(armLI, env); batch.render(armRI, env);
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
        FileHandle fh = Gdx.files.local(path);
        PixmapIO.writePNG(fh, pm);
        pm.dispose();
        Gdx.app.log("GHX", "saved " + path);
    }

    private void drawHud() {
        int w = Gdx.graphics.getWidth(), h = Gdx.graphics.getHeight();
        float u = unit();
        shapes.begin(ShapeRenderer.ShapeType.Filled);
        // chip trên trái
        shapes.setColor(0.05f, 0.12f, 0.19f, 0.78f);
        shapes.rect(10, h - 44 * u, 300 * u, 34 * u);
        // joystick
        shapes.setColor(0.05f, 0.12f, 0.19f, 0.38f);
        shapes.circle(joyCx(), joyCy(), joyR());
        shapes.setColor(1f, 0.85f, 0.54f, 0.92f);
        float kx = joyCx() + joyX * joyR() * 0.62f, ky = joyCy() - joyY * joyR() * 0.62f;
        shapes.circle(kx, ky, 27 * u);
        // nút bấm (luôn hiện)
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
        // tên trên đầu nhân vật
        Vector3 headPos = new Vector3(player.x, player.y + 2.9f, player.z).prj(cam.combined);
        if (headPos.z < 1) {
            float sx = (headPos.x * 0.5f + 0.5f) * w, sy = (headPos.y * 0.5f + 0.5f) * h;
            com.badlogic.gdx.graphics.g2d.GlyphLayout gl = new com.badlogic.gdx.graphics.g2d.GlyphLayout(font, player.name);
            font.draw(hud, player.name, sx - gl.width / 2, sy);
        }
        hud.end();
    }

    private void centerText(String text, float cx, float cy) {
        com.badlogic.gdx.graphics.g2d.GlyphLayout gl = new com.badlogic.gdx.graphics.g2d.GlyphLayout(fontBig, text);
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
