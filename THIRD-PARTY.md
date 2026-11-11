# 第三方组件与来源说明

本仓库**只包含补丁、文档和构建脚本**，不包含上游源码，也不分发任何二进制。下面是这套东西依赖的每一层，以及各自的许可与归属。

## 上游代码链

| 项目 | 作者 | 许可 | 本仓库与它的关系 |
|---|---|---|---|
| [andreavolpato/spektrafilm](https://github.com/andreavolpato/spektrafilm) | Andrea Volpato（KTH） | profiles 为 **CC BY-SA 4.0** | 光谱胶片/相纸模型、28 款实测配置、RA-4 印相与扫描链路的来源。本仓库一行都没有改它。 |
| [JamesQiu2005/SpektraLab](https://github.com/JamesQiu2005/SpektraLab) | Qiu Hanze（@JamesQiu2005） | **GPL-3.0-or-later** | 原生 C++/Metal 引擎移植与 macOS 应用。本仓库的补丁最终作用在这套代码的衍生版本上。 |
| [trouble123456/Film-Simulation](https://github.com/trouble123456/Film-Simulation) | — | **GPL-3.0-or-later**（继承） | SpektraLab 的 Windows 转译版（C++/Vulkan、LibRaw、Tauri 外壳）。补丁的基线是它的 v3.0.0 源码。 |

> 上游 README 自己的表述：`andreavolpato/spektrafilm`（CC BY-SA 4.0）→ `JamesQiu2005/SpektraLab`（GPL-3.0）→ Windows 转译版（GPL-3.0 继承）。

本项目与上述任何项目**均无隶属或背书关系**。

## RAW 解码

| 组件 | 许可 | 说明 |
|---|---|---|
| [LibRaw](https://www.libraw.org/) | **LGPL-2.1** 或 **CDDL-1.0**（二选一） | 所有 RAW 解码都由它完成。本补丁把它从 0.22.2 升到 0.23.0（202611 快照，commit `a9a14b1`）。**该快照里的 Nikon HE/HE\* 解码器是 LibRaw 项目自己的成果，不是本仓库写的。** |

上游工程选择 LGPL-2.1 分支并静态链接，产物目录里会带 `LICENSE.LGPL` 与 `COPYRIGHT`。重新分发编译产物时需要保留这些文件。

## 其他随软件分发的组件

以下是上游 Windows 版已经包含、本补丁没有改动的部分，列出仅供完整性参考：libjpeg-turbo、libpng、zlib-ng、LittleCMS、OpenEXR、libheif / libde265、Lensfun、GLib、PCRE2、libffi、stb、volk、Vulkan-Headers。各自的许可文本可在上游分发包的 `licenses/` 与 `third-party/` 目录中找到。

## 专利提示

Nikon 的 HE / HE\* 压缩基于 intoPIX 的 **TicoRAW**（JPEG XS 的私有变体），intoPIX 公开声明其受一项或多项专利保护。LibRaw 的解码器同样未获得授权。个人使用影响有限，**再分发请自行评估法律风险**。

## 关于"AI 生成"

本仓库的补丁、文档、脚本与验证记录由 AI 助手生成。上游代码、模型、算法、profile 数据的所有权与贡献完全属于上表中的作者。若本仓库的表述与上游文档冲突，以上游为准。
