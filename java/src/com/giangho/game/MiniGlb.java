package com.giangho.game;

import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.graphics.GL20;
import com.badlogic.gdx.graphics.Mesh;
import com.badlogic.gdx.graphics.VertexAttribute;
import com.badlogic.gdx.graphics.VertexAttributes;
import com.badlogic.gdx.graphics.g3d.Material;
import com.badlogic.gdx.graphics.g3d.Model;
import com.badlogic.gdx.graphics.g3d.attributes.ColorAttribute;
import com.badlogic.gdx.graphics.g3d.model.MeshPart;
import com.badlogic.gdx.graphics.g3d.model.Node;
import com.badlogic.gdx.graphics.g3d.model.NodePart;
import com.badlogic.gdx.math.Quaternion;
import com.badlogic.gdx.math.Vector3;
import com.badlogic.gdx.utils.JsonReader;
import com.badlogic.gdx.utils.JsonValue;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;

/** Nạp GLB tối giản cho model do Blender xuất: node có TRS + con, mesh POSITION/NORMAL + indices,
 *  vật liệu chỉ màu baseColorFactor. Đủ cho nhân vật mẫu J1.8. */
public class MiniGlb {
    private JsonValue json;
    private ByteBuffer bin;

    public static Model load(String path) {
        return new MiniGlb().parse(Gdx.files.local(path).readBytes());
    }

    private Model parse(byte[] data) {
        ByteBuffer buf = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);
        if (buf.getInt() != 0x46546C67) throw new IllegalArgumentException("không phải GLB");
        buf.getInt(); buf.getInt(); // version + length
        int jsonLen = buf.getInt();
        buf.getInt(); // 'JSON'
        byte[] jb = new byte[jsonLen];
        buf.get(jb);
        json = new JsonReader().parse(new String(jb, java.nio.charset.StandardCharsets.UTF_8));
        int binLen = buf.getInt();
        buf.getInt(); // 'BIN\0'
        byte[] bb = new byte[binLen];
        buf.get(bb);
        bin = ByteBuffer.wrap(bb).order(ByteOrder.LITTLE_ENDIAN);

        Model model = new Model();
        List<Material> materials = new ArrayList<>();
        JsonValue mats = json.get("materials");
        if (mats != null) {
            for (JsonValue mv : mats) {
                float r = 1, g = 1, b = 1;
                JsonValue pbr = mv.get("pbrMetallicRoughness");
                if (pbr != null && pbr.get("baseColorFactor") != null) {
                    JsonValue f = pbr.get("baseColorFactor");
                    r = f.getFloat(0); g = f.getFloat(1); b = f.getFloat(2);
                }
                Material m = new Material(ColorAttribute.createDiffuse(r, g, b, 1f));
                materials.add(m);
                model.materials.add(m);
            }
        }
        if (materials.isEmpty()) {
            Material m = new Material(ColorAttribute.createDiffuse(1, 1, 1, 1));
            materials.add(m);
            model.materials.add(m);
        }

        List<Mesh> meshes = new ArrayList<>();
        for (JsonValue meshJson : json.get("meshes")) {
            // Gom indices của mọi primitive vào 1 index buffer chung của mesh
            java.util.List<int[]> primIdx = new ArrayList<>();
            int totalIdx = 0;
            float[] pos = null, nor = null;
            for (JsonValue prim : meshJson.get("primitives")) {
                if (pos == null) {
                    pos = readFloats(prim.get("attributes").getInt("POSITION"), 3);
                    int norAcc = prim.get("attributes").getInt("NORMAL", -1);
                    nor = norAcc >= 0 ? readFloats(norAcc, 3) : null;
                }
                int[] idx = readIndices(prim.getInt("indices"));
                primIdx.add(idx);
                totalIdx += idx.length;
            }
            int verts = pos.length / 3;
            float[] interleaved = new float[verts * 6];
            for (int i = 0; i < verts; i++) {
                interleaved[i * 6] = pos[i * 3];
                interleaved[i * 6 + 1] = pos[i * 3 + 1];
                interleaved[i * 6 + 2] = pos[i * 3 + 2];
                interleaved[i * 6 + 3] = nor != null ? nor[i * 3] : 0;
                interleaved[i * 6 + 4] = nor != null ? nor[i * 3 + 1] : 1;
                interleaved[i * 6 + 5] = nor != null ? nor[i * 3 + 2] : 0;
            }
            short[] all = new short[totalIdx];
            int cursor = 0;
            for (int[] idx : primIdx) {
                for (int v : idx) all[cursor++] = (short) v;
            }
            Mesh mesh = new Mesh(true, verts, totalIdx,
                    new VertexAttribute(VertexAttributes.Usage.Position, 3, "a_position"),
                    new VertexAttribute(VertexAttributes.Usage.Normal, 3, "a_normal"));
            mesh.setVertices(interleaved);
            mesh.setIndices(all);
            meshes.add(mesh);
            model.meshes.add(mesh);
            int offset = 0;
            for (int[] idx : primIdx) {
                MeshPart part = new MeshPart("p" + model.meshParts.size, mesh, offset, idx.length, GL20.GL_TRIANGLES);
                model.meshParts.add(part);
                offset += idx.length;
            }
        }

        JsonValue scene = json.get("scenes").get(json.getInt("scene", 0));
        for (JsonValue rootIdx : scene.get("nodes")) {
            model.nodes.add(buildNode(rootIdx.asInt(), model, materials));
        }
        model.calculateTransforms();
        return model;
    }

    private Node buildNode(int idx, Model model, List<Material> materials) {
        JsonValue nj = json.get("nodes").get(idx);
        Node node = new Node();
        node.id = nj.getString("name", "node" + idx);
        if (nj.get("translation") != null) {
            JsonValue t = nj.get("translation");
            node.translation.set(t.getFloat(0), t.getFloat(1), t.getFloat(2));
        }
        if (nj.get("rotation") != null) {
            JsonValue r = nj.get("rotation");
            node.rotation.set(r.getFloat(0), r.getFloat(1), r.getFloat(2), r.getFloat(3));
        }
        if (nj.get("scale") != null) {
            JsonValue sc = nj.get("scale");
            node.scale.set(sc.getFloat(0), sc.getFloat(1), sc.getFloat(2));
        }
        if (nj.get("mesh") != null) {
            JsonValue meshJson = json.get("meshes").get(nj.getInt("mesh"));
            int meshPartCursor = countPartsBefore(nj.getInt("mesh"), model);
            int k = 0;
            for (JsonValue prim : meshJson.get("primitives")) {
                NodePart np = new NodePart();
                np.meshPart = model.meshParts.get(meshPartCursor + k);
                np.material = materials.get(prim.getInt("material", 0));
                node.parts.add(np);
                k++;
            }
        }
        if (nj.get("children") != null) {
            for (JsonValue c : nj.get("children")) node.addChild(buildNode(c.asInt(), model, materials));
        }
        return node;
    }

    private int countPartsBefore(int meshIdx, Model model) {
        int n = 0;
        for (int i = 0; i < meshIdx; i++) n += json.get("meshes").get(i).get("primitives").size;
        return n;
    }

    private float[] readFloats(int accIdx, int comps) {
        JsonValue acc = json.get("accessors").get(accIdx);
        JsonValue bv = json.get("bufferViews").get(acc.getInt("bufferView"));
        int count = acc.getInt("count");
        int stride = bv.getInt("byteStride", comps * 4);
        int offset = bv.getInt("byteOffset", 0) + acc.getInt("byteOffset", 0);
        float[] out = new float[count * comps];
        for (int i = 0; i < count; i++) {
            for (int c = 0; c < comps; c++) {
                out[i * comps + c] = bin.getFloat(offset + i * stride + c * 4);
            }
        }
        return out;
    }

    private int[] readIndices(int accIdx) {
        JsonValue acc = json.get("accessors").get(accIdx);
        JsonValue bv = json.get("bufferViews").get(acc.getInt("bufferView"));
        int count = acc.getInt("count");
        int type = acc.getInt("componentType");
        int offset = bv.getInt("byteOffset", 0) + acc.getInt("byteOffset", 0);
        int[] out = new int[count];
        for (int i = 0; i < count; i++) {
            if (type == 5123) out[i] = bin.getShort(offset + i * 2) & 0xFFFF;
            else if (type == 5125) out[i] = bin.getInt(offset + i * 4);
            else if (type == 5121) out[i] = bin.get(offset + i) & 0xFF;
        }
        return out;
    }
}
