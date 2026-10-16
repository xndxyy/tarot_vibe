# 塔罗 Vibe

一款以**本地中文牌义与三张牌抽取**为核心的 Flutter 塔罗应用，可按需调用 DeepSeek 生成中文解读。

不配置 API Key 也可以抽牌、翻牌和阅读本地牌义；AI 解读是需要联网与自备 Key 的可选功能。当前仓库适合作为 Flutter 交互、资源加载与模型 API 接入的学习原型，不是已经验证的商业发行版本。

## 已有功能

- **本地牌库**：当前实际加载 22 张大阿卡纳牌，包含中文名称、正位与逆位说明及对应图片。
- **三张牌抽取与翻牌**：输入问题后抽取三张牌，点击卡片查看牌面、方向与本地释义；支持重新开始。
- **基于问题的稳定抽取**：问题先经过文本规则归一化，再以哈希生成随机种子；相同归一化结果会得到相同牌组。这不是语义模型，也不保证不同说法一定被识别为同一问题。
- **可选 AI 解读**：把问题与三张牌按“过去、现在、未来”组织，调用 DeepSeek，提示模型给出总览、分牌解读、行动建议与风险提醒。
- **设备端 Key 设置**：提供 API Key 的保存、查看与清除界面，存储调用集中在 `ApiKeyStore`；同一问题的 AI 结果仅缓存在当前页面的内存中。

核心流程：

```text
输入问题 → 本地规则归一化 → 抽取三张牌并确定正逆位 → 点击翻牌
                                              └→ 可选：请求 DeepSeek 解读
```

## 本地启动

### 环境要求

以仓库现有依赖锁文件为基准：

| 项目 | 要求或说明 |
| --- | --- |
| Flutter | `pubspec.lock` 声明 `>=3.38.4`，同时需要满足下方 Dart 约束 |
| Dart | 锁文件要求 `>=3.10.3 <4.0.0`；不要只依据 `pubspec.yaml` 中较宽的 `>=3.3.0 <4.0.0` 判断 |
| Android 开发 | 需要对应 Android 工具链；仓库 Gradle 配置使用 Java 17 |
| 运行设备 | 已连接并被 Flutter 检测到的模拟器或真机 |

仓库包含 Android、iOS、Web、Windows、macOS、Linux 工程目录，但**目录存在不代表所有平台已经验证可用**，尤其需要单独核对安全存储插件与各平台权限、签名配置。

### 获取与运行

以下命令在本机已安装 Flutter 并配置目标平台工具链后执行：

```bash
git clone https://github.com/xndxyy/tarot_vibe.git
cd tarot_vibe

flutter doctor
flutter pub get
flutter devices
flutter run
```

`flutter doctor` 用于检查工具链，`flutter devices` 用于确认可用目标；`flutter run` 会在需要时让你选择设备。相关说明见 [Flutter 官方文档](https://docs.flutter.dev/)。

本 README 的启动步骤经过源码与配置静态核对，**未在本次文档整理中执行依赖安装、Flutter 构建或真机测试**。

## 开启 AI 深度解读

1. 启动应用，点击右上角钥匙图标进入“API 设置”。
2. 填写自己的 DeepSeek API Key 并保存。
3. 输入问题并完成抽牌，点击“AI 深度解读（DeepSeek）”。
4. 不再使用时，可在设置中选择“清除 Key”。

当前实现固定请求 `https://api.deepseek.com/v1/chat/completions`，模型名为 `deepseek-chat`，请求超时为 25 秒。接口、模型可用性、额度与费用以服务提供方实际情况为准，本仓库不附带可用 Key 或免费服务。

配置与隐私边界：

- Key 通过 `flutter_secure_storage` 写入设备端存储；具体保护能力仍依赖目标平台，不能视为整个应用已经通过安全审计。
- 用户保存的 Key 优先于源码中的编译期 `DEEPSEEK_API_KEY` 回退入口。**不要把个人或共享生产 Key 编入准备分发的客户端，也不要提交到仓库。**
- 只有点击 AI 解读时才会把问题、牌名、正逆位与本地牌义发送给 DeepSeek；本地抽牌不依赖这次请求。
- 没有账号系统或云端同步；页面中的抽牌状态、AI 结果与内存缓存不会作为历史记录持久保存。

## 代码导航

| 路径 | 内容 |
| --- | --- |
| [lib/main.dart](lib/main.dart) | 应用入口、主页、问题归一化、抽牌、翻牌交互、DeepSeek 请求及设置页 |
| [lib/service/api_key_store.dart](lib/service/api_key_store.dart) | API Key 的设备端读写与清除 |
| [assets/data/tarot.json](assets/data/tarot.json) | 当前实际参与抽牌的 22 张牌及中文释义 |
| [assets/images/](assets/images/) | 牌面图片；包含图片不等于已纳入牌库 |
| [pubspec.yaml](pubspec.yaml) / [pubspec.lock](pubspec.lock) | 依赖、资源声明与锁定版本 |
| [android/app/build.gradle.kts](android/app/build.gradle.kts) | Android 应用标识、工具链与签名配置 |

## 当前边界

- 当前不是完整的 78 张抽牌实现；小阿卡纳图片虽在资源目录中，但未被当前 JSON 牌库加载。
- AI 输出是生成式文本，不保证准确、一致或符合提示词要求。塔罗内容仅供娱乐与自我反思，不能据此作出医疗、法律、投资等重要决策。
- 仓库未提供业务自动化测试目录或 CI 流程；网络异常、不同屏幕尺寸与多平台行为仍需实际测试。
- Android 仍使用示例应用标识，release 配置使用 debug 签名；正式分发前需要补齐独立签名、平台配置与发布验证。
- 仓库当前未附带 LICENSE 文件。公开可读不等于授予任意复制、修改或商用权；复用代码及牌面素材前请向作者确认授权，并核对素材来源与权利。

