# Orbit 官网页网部署指南（隐私政策 / 支持页 / 首页）

> 提审前**必须**让 `privacy.html` 通过一个可公开访问的 URL 访问（App Store Connect 里要填）。
> 本目录 3 个页面均为零依赖静态 HTML，上传即用。支持邮箱统一为 **service.orbit@iChatStudio.com**；上线前须确认该邮箱可收信，并将三个页面一同部署。

## 页面清单

| 文件 | 用途 | App Store Connect 对应字段 |
|---|---|---|
| `privacy.html` | 隐私政策（中英） | App 信息 → 隐私政策 URL（**提审必填**） |
| `support.html` | 帮助与支持 FAQ | App 信息 → 支持 URL（**提审必填**） |
| `index.html` | 产品主页 | App 信息 → 营销 URL（可选，建议填） |

三个页面互相用相对链接引用，放在同一个目录下即可，无论部署在域名根目录还是子目录（如 `https://你的域名/orbit/`）都能正常跳转。

## 上线方式（三选一）

### 方式 A：已有云服务器（nginx / 宝塔 / 静态目录）—— 最快

把 3 个文件上传到站点目录，例如：

```bash
scp index.html privacy.html support.html user@你的服务器:/var/www/orbit/
# nginx 配置里让 https://你的域名/orbit/ 指向该目录即可
```

之后填入 ASC 的 URL：
- 隐私政策：`https://你的域名/orbit/privacy.html`
- 支持页：`https://你的域名/orbit/support.html`

### 方式 B：云厂商对象存储静态托管（无服务器也能上）

以阿里云 OSS / 腾讯云 COS 为例：
1. 创建 Bucket（读写权限设为"公共读"）
2. 上传 3 个文件
3. 绑定你的域名（首次需在 Bucket 域名管理里添加 CNAME）
4. 强烈建议开启 HTTPS（可用云厂商免费证书）——**ASC 的 URL 必须 https**

### 方式 C：GitHub Pages（免费，5 分钟，可先上车后绑域名）

1. 把 `website/` 目录推到仓库（已有仓库就放进去）
2. 仓库 Settings → Pages → Source 选 `main` 分支 `/ (root)` 或 `/website`（按放置位置）
3. 得到地址 `https://hanwen-FDE.github.io/orbit-scheduler/privacy.html`
4. （可选）以后在 Pages 设置里绑定你的自定义域名

## 部署后自测清单

- [ ] 手机流量（非 Wi-Fi）打开隐私政策 URL 能显示
- [ ] URL 是 https 且证书有效
- [ ] 页面无【待填】字样残留（Ctrl+F 全局搜"待填"）
- [ ] 三个页面互跳正常

## 占位符状态（✅ 全部完成）

| 位置 | 字段 | 状态 |
|---|---|---|
| index.html 页脚 | 开发者姓名 | ✅ Hanwen ZHANG |
| privacy.html 第一章 | 开发者姓名 | ✅ Hanwen ZHANG |
| index.html 页脚（mailto 链接） | 联系邮箱 | `service.orbit@iChatStudio.com` |
| privacy.html 第一章 + 第八章 | 联系邮箱（2 处） | `service.orbit@iChatStudio.com` |
| support.html 联系卡片 | 联系邮箱 | `service.orbit@iChatStudio.com` |
| （可选）三页页脚 | 备案号 | 中国区开放后再加，格式如"京ICP备2026XXXXXX号-X" |
