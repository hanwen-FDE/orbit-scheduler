# -*- coding: utf-8 -*-
"""把 使用说明书.md 转成自包含的 使用说明书.html (图片 base64 内嵌)。
运行: python make_docs_html.py
"""
import base64
import html
import re
from pathlib import Path

HERE = Path(__file__).parent
MD = (HERE / "使用说明书.md").read_text(encoding="utf-8")


def img_data_url(path):
    data = base64.b64encode(path.read_bytes()).decode()
    return f"data:image/png;base64,{data}"


def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"\[([^\]]+)\]\((https?:[^)\s]+)\)",
               r'<a href="\2" target="_blank" rel="noopener">\1</a>', s)
    return s


HEADER_RE = r"^(#{1,4}\s|>|\s*[-*]\s|\s*\d+\.\s|\||```|---+\s*$|!\[|<details)"


def render(lines):
    """把 markdown 行列表渲染为 HTML 片段列表。"""
    out = []
    i = 0
    while i < len(lines):
        ln = lines[i]

        # 代码块
        if ln.startswith("```"):
            i += 1
            buf = []
            while i < len(lines) and not lines[i].startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            out.append('<pre class="code">' + html.escape("\n".join(buf)) + "</pre>")
            continue

        # <details> 块: 渲染内部 markdown, 外面包 details 标签
        if ln.startswith("<details>"):
            summary_m = re.search(r"<summary>(.*?)</summary>", ln)
            i += 1
            buf = []
            while i < len(lines) and "</details>" not in lines[i]:
                buf.append(lines[i])
                i += 1
            i += 1
            summary = summary_m.group(1) if summary_m else "更多内容"
            if not summary_m and buf and buf[0].strip().startswith("<summary>"):
                summary = re.sub(r"</?summary>", "", buf[0]).strip()
                buf = buf[1:]
            inner = render([b for b in buf if b.strip()])
            out.append(f"<details><summary>{inline(summary)}</summary>"
                       + "\n".join(inner) + "</details>")
            continue

        # 表格
        if ln.strip().startswith("|") and i + 1 < len(lines) and \
                re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            head = [c.strip() for c in ln.strip().strip("|").split("|")]
            i += 2
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            t = '<div class="tblwrap"><table><thead><tr>'
            t += "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>"
            for r in rows:
                t += "<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>"
            out.append(t + "</tbody></table></div>")
            continue

        # 图片
        m = re.match(r"^!\[(.*?)\]\((.*?)\)\s*$", ln.strip())
        if m:
            p = HERE / m.group(2)
            out.append(f'<img class="fig" src="{img_data_url(p)}" alt="{m.group(1)}">')
            i += 1
            continue

        # 标题
        m = re.match(r"^(#{1,4})\s+(.*)$", ln)
        if m:
            lv = len(m.group(1))
            out.append(f"<h{lv}>{inline(m.group(2))}</h{lv}>")
            i += 1
            continue

        # 分隔线
        if re.match(r"^---+\s*$", ln):
            out.append("<hr>")
            i += 1
            continue

        # 引用块
        if ln.startswith(">"):
            buf = []
            while i < len(lines) and lines[i].startswith(">"):
                buf.append(lines[i].lstrip("> ").rstrip())
                i += 1
            out.append('<div class="quote">' +
                       "<br>".join(inline(b) for b in buf if b) + "</div>")
            continue

        # 无序列表
        if re.match(r"^\s*[-*]\s+", ln):
            buf = []
            while i < len(lines) and re.match(r"^\s*[-*]\s+", lines[i]):
                buf.append(re.sub(r"^\s*[-*]\s+", "", lines[i]).rstrip())
                i += 1
            out.append("<ul>" + "".join(f"<li>{inline(b)}</li>" for b in buf) + "</ul>")
            continue

        # 有序列表
        if re.match(r"^\s*\d+\.\s+", ln):
            buf = []
            while i < len(lines) and re.match(r"^\s*\d+\.\s+", lines[i]):
                buf.append(re.sub(r"^\s*\d+\.\s+", "", lines[i]).rstrip())
                i += 1
            out.append("<ol>" + "".join(f"<li>{inline(b)}</li>" for b in buf) + "</ol>")
            continue

        # 空行
        if not ln.strip():
            i += 1
            continue

        # 普通段落 (合并到下一个块级元素为止)
        buf = [ln.rstrip()]
        i += 1
        while i < len(lines) and lines[i].strip() and not re.match(HEADER_RE, lines[i]):
            buf.append(lines[i].rstrip())
            i += 1
        out.append("<p>" + "<br>".join(inline(b) for b in buf) + "</p>")
    return out


TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Orbit·轨道 日程助手 · 快捷指令版 使用说明书</title>
<style>
  :root {{
    --ink: #2d3159; --muted: #7a809c; --violet: #6c5ce7;
    --violet-soft: #edecfe; --border: #e4e7f0;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; background: #f6f7fb; color: var(--ink);
    font: 16px/1.75 -apple-system, "PingFang SC", "Microsoft YaHei",
          "Segoe UI", sans-serif;
  }}
  .page {{ max-width: 860px; margin: 0 auto; padding: 28px 20px 80px; }}
  h1 {{ font-size: 26px; margin: 30px 0 6px; }}
  h2 {{
    font-size: 21px; margin: 44px 0 14px; padding-left: 14px;
    border-left: 5px solid var(--violet);
  }}
  h3 {{ font-size: 18px; margin: 26px 0 10px; }}
  p {{ margin: 10px 0; }}
  a {{ color: var(--violet); }}
  img.fig {{
    width: 100%; border-radius: 14px; border: 1px solid var(--border);
    margin: 14px 0; background: #fff; display: block;
  }}
  .quote {{
    background: var(--violet-soft); border-radius: 12px;
    padding: 14px 18px; margin: 14px 0; color: #4a4680;
  }}
  code {{
    background: #eef0f7; border-radius: 6px; padding: 2px 7px;
    font-size: 14px; font-family: "Cascadia Code", Consolas, monospace;
    color: #5b4fc4; word-break: break-all;
  }}
  pre.code {{
    background: #23264a; color: #e8e9fb; border-radius: 12px;
    padding: 16px 18px; overflow-x: auto; line-height: 1.6;
    font-size: 13.5px; font-family: "Cascadia Code", Consolas, monospace;
  }}
  .tblwrap {{ overflow-x: auto; margin: 14px 0; }}
  table {{
    border-collapse: collapse; width: 100%; background: #fff;
    border-radius: 12px; overflow: hidden; font-size: 14.5px;
  }}
  th, td {{ border: 1px solid var(--border); padding: 9px 12px; text-align: left; }}
  th {{ background: #f0f1f9; }}
  tr:nth-child(even) td {{ background: #fafbfd; }}
  ul, ol {{ padding-left: 24px; }}
  li {{ margin: 4px 0; }}
  hr {{ border: none; border-top: 1px solid var(--border); margin: 30px 0; }}
  footer {{ text-align: center; color: var(--muted); margin-top: 50px; }}
  details {{
    background: #fff; border: 1px solid var(--border); border-radius: 12px;
    padding: 4px 16px; margin: 12px 0;
  }}
  details summary {{ cursor: pointer; font-weight: 600; padding: 8px 0; }}
  details[open] summary {{ border-bottom: 1px dashed var(--border); margin-bottom: 8px; }}
</style>
</head>
<body>
<div class="page">
{body}
<footer>Orbit·轨道 —— All your plans run on time orbit. 🪐</footer>
</div>
</body>
</html>
"""

html_out = TEMPLATE.format(body="\n".join(render(MD.splitlines())))
(HERE / "使用说明书.html").write_text(html_out, encoding="utf-8")
print("OK 使用说明书.html", f"({len(html_out)//1024} KB, 图片已内嵌)")
