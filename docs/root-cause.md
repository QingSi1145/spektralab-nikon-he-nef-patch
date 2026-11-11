# 排查记录：Z50II 的 NEF 为什么打不开

这是一次事后整理的排查记录，按实际顺序写，包含每一步的命令和输出，方便别人复核。

## 1. 现象

软件能浏览文件夹、能显示缩略图，但选中照片后导入失败。直接跟 `filmlab-host.exe` 对话（它用长度前缀的 JSON 帧走 stdin/stdout，见上游 `desktop/HOST-PROTOCOL.md`）得到：

```json
{"id": 2, "ok": true,  "result": {"width": 3728, "height": 5600, "kind": "raw",
  "metadata": {"model": "Z50_2", "lens": "NIKKOR Z DX 16-50mm f/3.5-6.3 VR", "iso": 100}}}
{"id": 3, "ok": true,  "result": {"source": "embedded", "orientation_applied": true}}
{"id": 4, "ok": false, "error": {"code": "decode_failed",
  "message": "RAW unpack: decoder reported corrupt data"}}
```

关键点：`probe`（只读元数据）成功，`thumbnail` 成功且 `source` 是 `"embedded"`（内嵌 JPEG 预览），只有 `open`（真正解码 RAW）失败。所以这不是"文件损坏"，也不是"格式不认识"。

## 2. 看文件本身

读 TIFF 结构（IFD0 的 SubIFD 才是真正的 RAW 图）：

| 项 | 值 |
|---|---|
| 字节序 | `II`，magic 42 |
| Make / Model | `NIKON CORPORATION` / `NIKON Z50_2` |
| 固件 | `Ver.01.11` |
| 主图像 Compression | `34713`（Nikon NEF 私有压缩） |
| 主图像 BitsPerSample | 14 |
| 主图像条带偏移 | 0x3EB000 |
| 主图像字节数 | 13,047,808 |
| 原始尺寸 | 5600 × 3728 |

5600 × 3728 × 14 bit ≈ 36.5 MB 的原始数据被压到 13 MB —— 说明是强压缩。

再看主图像偏移处的前 4 个字节：

```
FF 10 FF 50
```

`FF10` 是 JPEG XS 的 SOC（Start of Codestream），`FF50` 是 CAP（Capabilities）。这正是 Nikon 所谓"高效（HE）/ 高效★（HE\*）"压缩 —— 底层是 intoPIX 的 TicoRAW，一个 JPEG XS 的私有变体。HE 大约 3 bit/像素，HE\* 大约 5 bit/像素，无损则是 14 bit。

## 3. 看 LibRaw 0.22.2

三个独立的缺口：

**(a) 解码器是空的。** `src/decoders/decoders_libraw_dcrdefs.cpp`：

```cpp
void LibRaw::nikon_he_load_raw()
{
    if(dng_version)
        throw LIBRAW_EXCEPTION_UNSUPPORTED_FORMAT; // Never reached
    throw LIBRAW_EXCEPTION_UNSUPPORTED_FORMAT;
}
```

**(b) 没认出这台机器。** `src/metadata/tiff.cpp` 里对 HE 的识别写死了机型：

```cpp
else if ((!strncmp(model, "NIKON Z 9", 9) || !strncmp(model, "NIKON Z 8", 9)
          || !strcmp(model, "NIKON Z f") || !strcmp(model, "NIKON Z6_3"))
         && tiff_ifd[raw].offset)
```

`Z50_2` 三个条件一个都不满足，于是交给 `break` 之后的默认分支 `load_raw = &LibRaw::nikon_load_raw;` —— 拿 JPEG XS 的码流当 Nikon 无损压缩解，结果就是 "data corrupted"。

**(c) 没有色彩矩阵。** `src/tables/colordata.cpp` 的 `adobe_coeff` 表里只有 `Z 30 / Z 50 / Z 5 / Z 6 / Z 6_3 / Z 7 / Z 8 / Z 9 / Z f / Z fc`，没有 `Z50_2`。前缀匹配也救不了：`"Z 50"` 和 `"Z50_2"` 在空格处就对不上。

结论：**(c) 意味着即使拍无损压缩 NEF，颜色也是错的；(a)(b) 意味着 HE NEF 根本打不开。**

## 4. 上游什么时候补的

LibRaw 在 **2026-11-07** 发布的 202611 快照（版本号 0.23.0，`LIBRAW_VERSION_TAIL Snapshot202611`）里，更新说明的第一行就是：

> Nikon HE/HE\* format (Z6-III, Z8, Z9, Zf cameras)

而这个快照另外还做了三件与本问题直接相关的事：

- `tiff.cpp` 的识别分支加上了 `NIKON Z50_2`、`NIKON Z5_2`、`NIKON ZR`；
- `colordata.cpp` 增加了 `Z50_2` 的矩阵：`{11640,-4829,-1079,-5107,13006,2325,-972,1711,7380}`；
- `src/decoders/nikonhe.cpp` 是真正的 TicoRAW 解码实现。

所以修复方向不是逆向，而是**升级依赖**。

## 5. 先单独验证 LibRaw 能不能解

在动应用之前，先用最小程序确认新库确实解得开（避免白编一整个工程）：

```cpp
LibRaw raw(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK);
raw.open_file(argv[1]);
raw.unpack();
printf("%s %s\n", raw.imgdata.idata.model, raw.unpack_function_name());
```

对同一张 NEF 的输出：

```
libraw    : 0.23.0-Snapshot202611
make/model: Nikon / Z50_2
size      : 5600x3728  raw 5600x3728  colors 3  filters b4b4b4b4
black/max : 1008 / 16383
cam_mul   : 1.7812 1.0000 1.5703 1.0000
cam_xyz   : [1.1640 -0.4829 -0.1079][-0.5107 1.3006 0.2325][-0.0972 0.1711 0.7380]
unpack    : 0 (No error)  decoder=nikon_he_load_raw()
mosaic    : n=1043840 mean=2436.7 min=1011 max=12638
```

`decoder=nikon_he_load_raw()` 说明确实走了新解码器；mosaic 的 min 1011 贴着 black 1008、max 12638 远低于 16383，统计分布正常（不是噪声）；`cam_xyz` 也非零。解码结果与相机的 JPEG 目视一致。

## 6. 应用侧还有一道拦截

换上新的 LibRaw 之后，`open` 依然失败，但错误变了：

```
RAW unpack (Z50_2): Nikon HE/HE* compression is not supported by
bundled LibRaw 0.23.0-Snapshot202611; use a lossless-compressed NEF
or externally converted RAW DNG
```

这条消息来自 `engine/src/io/raw_decoder.cpp` 的 `supported_compression()` —— 它按**解码器名字**否决：

```cpp
if (decoder && std::strstr(decoder, "nikon_he_load_raw") != nullptr) { ... return false; }
```

这是 0.22.2 时代为了让用户看到一句人话而加的，在 0.23.0 下会误杀能解的文件。删掉之后 `open` 通过，`decode 354 ms`。

## 7. 为什么钉 commit 而不是 master

`setup-libraw.ps1` 原来下载 `refs/tags/0.22.2`。快照不是 tag，`master` 又是移动的，所以改成钉到 commit `a9a14b1`，附 SHA-256，并在解压后断言 `LIBRAW_VERSION_TAIL` 是 `Snapshot202611` —— 否则拒绝安装。这样"验证过的树"和"构建出来的树"是同一棵。

## 8. 复现命令

```powershell
# 1. 打补丁
cd <src>
git apply z50ii-he-support.patch

# 2. 取依赖
.\engine\setup-libraw.ps1 -DependencyDirectory C:\spk\deps
.\engine\setup-codecs.ps1 -DependencyDirectory C:\spk\deps\export-codecs

# 3. 配置与构建（完整参数见 build-host.ps1）
cmake -S . -B C:\spk\build -G Ninja -DCMAKE_BUILD_TYPE=Release `
  -DSPEKTRALAB_BUILD_NATIVE_RAW=ON -DSPEKTRALAB_BUILD_HOST=ON `
  -DSPEKTRALAB_BUILD_DESKTOP=OFF -DSPEKTRALAB_REQUIRE_VULKAN=ON -DBUILD_TESTING=OFF `
  -DSPEKTRALAB_LIBRAW_SOURCE=C:/spk/deps/LibRaw-0.23.0
cmake --build C:\spk\build --target filmlab-host -j 8
```

## 附：一个与本次修复无关的坑

从带 **Medium 完整性标签**的目录（例如被沙箱标记过的工作目录）启动该应用时，Tauri 会崩在：

```
Failed to setup app: failed to create webview: WebView2 error: WindowsError(HRESULT(0x80070005), "拒绝访问")
```

把程序放到普通目录、纯 ASCII 路径下启动即可。这不是补丁引起的，原版程序同样如此。
