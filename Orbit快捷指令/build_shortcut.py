# -*- coding: utf-8 -*-
"""
Orbit·轨道 日程助手 —— iOS 快捷指令生成器
=============================================

运行:  python build_shortcut.py

产出:
  1. Orbit轨道日程助手.shortcut   (XML plist, 可被"快捷指令"App 识别的工程文件)
  2. 源码速览.md                   (人类可读的动作清单, 供检查与手动复刻)

设计原则: 所有可自定义项集中在最上方的「配置」字典里, 用户改字典即可换
服务商/模型/日历/提醒, 无需理解后面的动作流。
"""

import plistlib
import uuid
from pathlib import Path

HERE = Path(__file__).parent

# ----------------------------------------------------------------------
# 提示词 (与 App 版 ScheduleAssistant/Sources/LLMProvider.swift 保持一致,
# 针对快捷指令场景微调: 结束时间不再允许 null, 全天日程用起止区间表达)
# ----------------------------------------------------------------------
SYSTEM_PROMPT = (
    "你是一个日程信息提取助手。从用户提供的文字或图片中提取**所有**日程安排，"
    "严格返回 JSON（不要任何其他文字、不要 markdown 代码块），格式为：\n"
    '{"events": [{...}, {...}]}\n'
    "每个元素的字段：\n"
    '{"title": "日程标题(字符串,必填,简短)", "emoji": "一个最贴合日程主题的emoji字符", '
    '"startDate": "开始时间,ISO8601格式如2026-09-10T14:00:00+08:00", '
    '"endDate": "结束时间,ISO8601格式", "location": "地点,可null", '
    '"notes": "补充说明,可null", "isAllDay": 是否全天(布尔,默认false), '
    '"confidence": 置信度0到1的小数}\n'
    "注意：\n"
    "- 内容里有几项日程，events 数组就放几个元素：整场会议只给名称和起止时间时输出 1 项；"
    "多行罗列的日程表（每行一项）要逐项输出，不可合并。\n"
    "- 用户没说年份时按当前时间推算合理的年份；没说结束时间时，endDate 按开始时间加 1 小时推算，"
    "不要输出 null。\n"
    "- 全天日程 startDate 用当天 00:00:00，endDate 用当天 23:59:59。\n"
    "- 重复性日程（如「每周二、四晚8点，共8周」）要展开为每一个具体日期的事件，逐个输出。\n"
    "- 当前系统时间会随用户消息一并提供。\n"
    "- 如果内容里完全没有日程信息，返回 {\"events\": []}。"
)

# 默认配置 (用户在快捷指令编辑器顶部「配置」字典中修改)
DEFAULT_CONFIG = {
    "API地址": "https://open.bigmodel.cn/api/paas/v4",
    "API密钥": "请把这一行替换成你的API密钥",
    "模型": "glm-4v-plus",
    "目标日历": "",
    "提前提醒分钟": 15,
}

# ======================================================================
# 序列化小工具
# ======================================================================
OBJ = "\ufffc"  # 快捷指令魔术变量的占位字符 (U+FFFC)


def var_ref(name):
    """让某个参数整体引用一个命名变量。"""
    return {
        "Value": {"Type": "Variable", "VariableName": name},
        "WFSerializationType": "WFVariablePayload",
    }


def act(identifier, params=None):
    return {
        "WFWorkflowActionIdentifier": identifier,
        "WFWorkflowActionParameters": params or {},
    }


# ---- 字典 (WFItems) 构造 ---------------------------------------------
def _wf_str_value(value):
    return {"Value": {"string": value}}


def d_text(parts_or_str):
    """字符串项; parts_or_str 为 token parts 列表时携带变量。"""
    if isinstance(parts_or_str, str):
        parts_or_str = [("lit", parts_or_str)]
    inner = {"string": ""}
    s = ""
    attachments = {}
    for kind, val in parts_or_str:
        if kind == "lit":
            s += val
        else:
            start = len(s.encode("utf-16-le")) // 2
            s += OBJ
            attachments[f"{{{start}, 1}}"] = {
                "Type": "Variable",
                "VariableName": val,
            }
    inner["string"] = s
    if attachments:
        inner["attachmentsByRange"] = attachments
        return {"Value": inner, "WFSerializationType": "WFTextTokenString"}
    return {"Value": inner}


def d_number(x):
    return {"Value": {"number": x}}


def d_bool(x):
    return {"Value": {"bool": x}}


def d_items(pairs):
    """pairs: [(key, (WFItemType, WFValue)), ...]"""
    items = []
    for key, (itype, val) in pairs:
        item = {
            "WFItemType": itype,
            "WFKey": _wf_str_value(key),
            "WFValue": val,
        }
        items.append(item)
    return {"Value": {"WFDictionaryFieldValueItems": items}}


def kv_str(key, parts_or_str):
    return (key, (0, d_text(parts_or_str)))


def kv_num(key, x):
    return (key, (1, d_number(x)))


def kv_bool(key, x):
    return (key, (2, d_bool(x)))


def kv_dict(key, pairs):
    return (key, (3, d_items(pairs)))


def kv_arr(key, elements):
    """elements: [(WFItemType, WFValue), ...]"""
    return (key, (4, {"Value": {"WFDictionaryFieldValueItems": [
        {"WFItemType": t, "WFKey": _wf_str_value(""), "WFValue": v}
        for t, v in elements
    ]}}))


# 常用动作标识
A = {
    "dictionary": "is.workflow.actions.dictionary",
    "setvariable": "is.workflow.actions.setvariable",
    "get_dict_value": "is.workflow.actions.dictionaryvalue",
    "detect_text": "is.workflow.actions.detect.text",
    "detect_dict": "is.workflow.actions.detect.dictionary",
    "conditional": "is.workflow.actions.conditional",
    "menu": "is.workflow.actions.choosefrommenu",
    "ask": "is.workflow.actions.ask",
    "dictate": "is.workflow.actions.dictate-text",
    "select_photo": "is.workflow.actions.selectphoto",
    "base64": "is.workflow.actions.base64encode",
    "date": "is.workflow.actions.date",
    "format_date": "is.workflow.actions.format.date",
    "text": "is.workflow.actions.text",
    "replace": "is.workflow.actions.text.replace",
    "url_contents": "is.workflow.actions.downloadurl",
    "count": "is.workflow.actions.count",
    "repeat": "is.workflow.actions.repeat.each",
    "add_event": "is.workflow.actions.addevent",
    "alert": "is.workflow.actions.alert",
    "result": "is.workflow.actions.showresult",
    "exit": "is.workflow.actions.exit",
    "haptic": "is.workflow.actions.vibrate",
}


def set_var(name):
    """把上一个动作的输出存入命名变量。"""
    return act(A["setvariable"], {"WFVariableName": name})


def get_key(source_var, key):
    return act(A["get_dict_value"], {
        "WFDictionaryKey": key,
        "WFInput": var_ref(source_var),
    })


def new_gid():
    return str(uuid.uuid4()).upper()


# ======================================================================
# 动作流
# ======================================================================
actions = []
flow_log = []  # (动作名, 说明)
GROUP_STACK = []  # 当前打开的控制流组 (If / 菜单 / 重复)

FLOW_IDENTIFIERS = {A["conditional"], A["menu"], A["repeat"]}

ACTION_NAMES = {
    A["dictionary"]: "字典", A["setvariable"]: "设定变量",
    A["get_dict_value"]: "获取词典值", A["detect_text"]: "从输入获取文本",
    A["detect_dict"]: "从输入获取词典", A["conditional"]: "If",
    A["menu"]: "菜单", A["ask"]: "请求输入", A["dictate"]: "听写文本",
    A["select_photo"]: "选择照片", A["base64"]: "Base64 编码",
    A["date"]: "当前日期", A["format_date"]: "格式化日期",
    A["text"]: "文本", A["replace"]: "替换文本",
    A["url_contents"]: "获取 URL 内容", A["count"]: "统计数量",
    A["repeat"]: "重复每个项目", A["add_event"]: "添加新日程",
    A["alert"]: "显示提醒", A["result"]: "显示结果",
    A["exit"]: "停止此快捷指令", A["haptic"]: "振动",
}


def add(action, desc):
    """普通动作: 自动归入最内层控制流组。"""
    if GROUP_STACK:
        action["WFWorkflowActionParameters"]["GroupingIdentifier"] = GROUP_STACK[-1][1]
    actions.append(action)
    flow_log.append((ACTION_NAMES.get(
        action["WFWorkflowActionIdentifier"], "?"), desc))
    return action


def if_start(var, cond_desc, extra=None):
    gid = new_gid()
    params = {"GroupingIdentifier": gid, "WFControlFlowMode": 0,
              "WFCondition": "String", "WFInput": var_ref(var)}
    params.update(extra or {})
    a = act(A["conditional"], params)
    actions.append(a)
    flow_log.append(("If", f"If [{var}] {cond_desc}"))
    GROUP_STACK.append(("if", gid))
    return gid


def if_else(gid):
    GROUP_STACK.pop()  # 离开 true 分支
    a = act(A["conditional"], {"GroupingIdentifier": gid, "WFControlFlowMode": 1})
    actions.append(a)
    flow_log.append(("If", "否则 Otherwise"))
    GROUP_STACK.append(("if-else", gid))


def if_end(gid):
    GROUP_STACK.pop()
    a = act(A["conditional"], {"GroupingIdentifier": gid, "WFControlFlowMode": 2})
    actions.append(a)
    flow_log.append(("If", "结束 If"))


def menu_start(prompt, items):
    gid = new_gid()
    a = act(A["menu"], {
        "GroupingIdentifier": gid,
        "WFControlFlowMode": 0,
        "WFMenuPrompt": prompt,
        "WFMenuItems": [{"WFMenuItemTitle": t} for t in items],
    })
    actions.append(a)
    flow_log.append(("菜单", f"菜单 «{prompt}»"))
    GROUP_STACK.append(("menu", gid))
    return gid


def menu_next_item(gid, title):
    a = act(A["menu"], {"GroupingIdentifier": gid, "WFControlFlowMode": 2})
    actions.append(a)
    flow_log.append(("菜单", f"— 菜单项: {title}"))


def menu_end(gid):
    GROUP_STACK.pop()
    a = act(A["menu"], {"GroupingIdentifier": gid, "WFControlFlowMode": 1})
    actions.append(a)
    flow_log.append(("菜单", "结束菜单"))


def repeat_start(list_var):
    gid = new_gid()
    a = act(A["repeat"], {
        "GroupingIdentifier": gid,
        "WFControlFlowMode": 0,
        "WFInput": var_ref(list_var),
    })
    actions.append(a)
    flow_log.append(("重复每个项目", f"重复 [{list_var}] 中的每个项目"))
    GROUP_STACK.append(("repeat", gid))
    return gid


def repeat_end(gid):
    GROUP_STACK.pop()
    a = act(A["repeat"], {"GroupingIdentifier": gid, "WFControlFlowMode": 2})
    actions.append(a)
    flow_log.append(("重复每个项目", "结束重复"))


# ----------------------------------------------------------------------
# ① 配置字典 (用户唯一需要编辑的地方)
# ----------------------------------------------------------------------
add(act(A["dictionary"], {
    "WFName": "配置",
    "WFItems": d_items([
        kv_str("API地址", DEFAULT_CONFIG["API地址"]),
        kv_str("API密钥", DEFAULT_CONFIG["API密钥"]),
        kv_str("模型", DEFAULT_CONFIG["模型"]),
        kv_str("目标日历", ""),
        kv_num("提前提醒分钟", DEFAULT_CONFIG["提前提醒分钟"]),
    ]),
}), "「配置」字典 —— 用户自定义区 (API地址/密钥/模型/日历/提醒)")
add(set_var("配置"), "存为变量 [配置]")

# 读取各配置项
for key, var in [("API地址", "API地址"), ("API密钥", "API密钥"),
                 ("模型", "模型"), ("目标日历", "目标日历"),
                 ("提前提醒分钟", "提醒分钟")]:
    add(get_key("配置", key), f"从[配置]取值: {key}")
    add(set_var(var), f"存为变量 [{var}]")

# 密钥未配置 → 友好提示并停止
gid = if_start("API密钥", "包含「请把这一行替换」",
               {"WFStringCondition": "Contains",
                "WFConditionalActionString": "请把这一行替换"})
add(act(A["alert"], {
    "WFAlertActionTitle": "⏳ 还差一步",
    "WFAlertActionMessage": "请先填写 API 密钥：长按本快捷指令 → 编辑 → 打开最上方的「配置」字典，把「API密钥」一行的占位文字换成你的密钥（详见使用说明书）。改完再运行即可。",
    "WFAlertActionCancelButtonShown": False,
}), "显示提醒: 请先配置 API 密钥")
add(act(A["exit"]), "停止此快捷指令")
if_end(gid)

# ----------------------------------------------------------------------
# ② 获取日程内容 (分享表单直达 / 文字 / 语音 / 图片)
# ----------------------------------------------------------------------
add(act(A["detect_text"]), "获取「快捷指令输入」的文本 (从分享表单进入时)")
add(set_var("输入文本"), "存为变量 [输入文本]")

# 图片数据占位
add(act(A["text"], {"WFTextActionText": d_text("")}), "空文本")
add(set_var("图片数据"), "存为变量 [图片数据] = 空")

gid = if_start("输入文本", "有值", {"WFCondition": "Exists"})
add(set_var("日程文本"), "存为变量 [日程文本] = 分享来的文本")
if_else(gid)
gid_menu = menu_start("✨ Orbit·轨道：选择输入方式",
                      ["⌨️ 输入或粘贴文字", "🎙️ 语音听写", "📷 识别图片"])
# -- 菜单项 1: 文字
add(act(A["ask"], {
    "WFAskActionPrompt": "要记录的日程（支持一次粘贴多行）",
    "WFAskActionDefaultAnswer": "例：周五下午3点开会；10月1日到7日国庆假期；下周二晚8点瑜伽课",
}), "请求输入: 要记录的日程")
add(set_var("日程文本"), "存为变量 [日程文本]")
menu_next_item(gid_menu, "🎙️ 语音听写")
# -- 菜单项 2: 语音
add(act(A["dictate"]), "听写文本 (语音转文字)")
add(set_var("日程文本"), "存为变量 [日程文本]")
menu_next_item(gid_menu, "📷 识别图片")
# -- 菜单项 3: 图片
add(act(A["select_photo"], {"WFSelectPhotoActionSelectMultiple": False}),
    "选择照片 (课程表/会议通知截图)")
add(act(A["base64"], {"WFBase64EncodeMode": "Encode"}), "Base64 编码")
add(act(A["text"], {"WFTextActionText": d_text([
    ("lit", "data:image/jpeg;base64,"), ("var", "Base64编码的图片"),
])}), "拼出图片 data URL")
add(set_var("图片数据"), "存为变量 [图片数据]")
add(act(A["text"], {"WFTextActionText": d_text(
    "请识别图片中的所有日程安排。")}), "图片分支的文字说明")
add(set_var("日程文本"), "存为变量 [日程文本]")
menu_end(gid_menu)
if_end(gid)

# 当前时间 (供模型推算年份/星期)
add(act(A["date"]), "当前日期")
add(act(A["format_date"], {
    "WFDateFormatStyle": "Custom",
    "WFDateFormatFormat": "yyyy-MM-dd HH:mm EEEE",
}), "格式化日期: yyyy-MM-dd HH:mm EEEE")
add(set_var("当前时间"), "存为变量 [当前时间]")

# ----------------------------------------------------------------------
# ③ 组装请求体 (纯类型化字典, 换行/引号由系统自动转义)
# ----------------------------------------------------------------------
system_content = kv_arr("content", [(0, d_text(
    [("lit", SYSTEM_PROMPT)]))])
message_system = {
    "WFItemType": 3,
    "WFKey": _wf_str_value(""),
    "WFValue": d_items([
        kv_str("role", "system"),
        system_content,
    ]),
}


def message_user(content_pairs):
    return {
        "WFItemType": 3,
        "WFKey": _wf_str_value(""),
        "WFValue": d_items([
            kv_str("role", "user"),
            kv_arr("content", content_pairs),
        ]),
    }


user_text_content = (0, d_text([("lit", "（当前时间："), ("var", "当前时间"),
                                ("lit", "）\n"), ("var", "日程文本")]))

gid = if_start("图片数据", "包含「base64,」",
               {"WFStringCondition": "Contains",
                "WFConditionalActionString": "base64,"})
body_image = d_items([
    kv_str("model", [("var", "模型")]),
    kv_arr("messages", [
        (3, message_system["WFValue"]),
        (3, message_user([
            (0, d_text([("lit", "请识别图片中的所有日程安排。")])),
            (3, d_items([
                kv_str("type", "image_url"),
                kv_dict("image_url", [kv_str(
                    "url", [("lit", "data:image/jpeg;base64,"),
                            ("var", "图片数据")])]),
            ])),
        ])["WFValue"]),
    ]),
    kv_num("temperature", 0.1),
])
add(act(A["dictionary"], {
    "WFName": "请求体(图片)",
    "WFItems": body_image,
}), "构造请求体: 文字+图片 (多模态)")
add(set_var("请求体"), "存为变量 [请求体]")
if_else(gid)
body_text = d_items([
    kv_str("model", [("var", "模型")]),
    kv_arr("messages", [
        (3, message_system["WFValue"]),
        (3, message_user([user_text_content])["WFValue"]),
    ]),
    kv_num("temperature", 0.1),
])
add(act(A["dictionary"], {
    "WFName": "请求体(文字)",
    "WFItems": body_text,
}), "构造请求体: 纯文字")
add(set_var("请求体"), "存为变量 [请求体]")
if_end(gid)

# 完整接口地址
add(act(A["text"], {"WFTextActionText": d_text([
    ("var", "API地址"), ("lit", "/chat/completions"),
])}), "拼接接口地址: [API地址]/chat/completions")
add(set_var("接口地址"), "存为变量 [接口地址]")

# ----------------------------------------------------------------------
# ④ 调用大模型
# ----------------------------------------------------------------------
add(act(A["url_contents"], {
    "WFURL": {"Value": {"string": OBJ}, "attachmentsByRange": {
        "{0, 1}": {"Type": "Variable", "VariableName": "接口地址"}},
        "WFSerializationType": "WFTextTokenString"},
    "Advanced": True,
    "Method": "POST",
    "WFHTTPHeaders": d_items([
        kv_str("Content-Type", "application/json"),
        kv_str("Authorization", [("lit", "Bearer "), ("var", "API密钥")]),
    ]),
    "WFHTTPBodyType": "JSON",
    "WFJSONValues": var_ref("请求体"),
}), "获取 URL 内容: POST [接口地址] (JSON 请求体=[请求体], 带 Bearer 密钥)")
add(set_var("响应"), "存为变量 [响应]")

# ----------------------------------------------------------------------
# ⑤ 解析模型返回 → 事件列表
# ----------------------------------------------------------------------
add(get_key("响应", "choices.0.message.content"),
    "从[响应]取值: choices.0.message.content")
add(set_var("模型回复"), "存为变量 [模型回复]")

# 容错: 剥离模型可能在 JSON 前后输出的多余文字/代码块围栏
add(act(A["replace"], {
    "WFInput": var_ref("模型回复"),
    "WFReplaceTextFind": "^[^{]*",
    "WFReplaceTextReplace": "",
    "WFReplaceTextRegularExpression": True,
    "WFReplaceTextCaseSensitive": False,
}), "正则替换: 去掉第一个 { 之前的内容")
add(act(A["replace"], {
    "WFReplaceTextFind": "[^}]*$",
    "WFReplaceTextReplace": "",
    "WFReplaceTextRegularExpression": True,
    "WFReplaceTextCaseSensitive": False,
}), "正则替换: 去掉最后一个 } 之后的内容")
add(set_var("内容JSON"), "存为变量 [内容JSON]")

gid = if_start("内容JSON", "包含「{」", {
    "WFStringCondition": "Contains", "WFConditionalActionString": "{"})
if_else(gid)
add(act(A["alert"], {
    "WFAlertActionTitle": "🤔 没有识别到日程",
    "WFAlertActionMessage": "模型没有返回日程信息。可以换个说法再试，或检查所选模型是否支持图片。",
    "WFAlertActionCancelButtonShown": False,
}), "显示提醒: 没有识别到日程")
add(act(A["exit"]), "停止此快捷指令")
if_end(gid)

add(act(A["detect_dict"], {"WFInput": var_ref("内容JSON")}),
    "从输入获取词典 (解析 JSON)")
add(set_var("日程数据"), "存为变量 [日程数据]")
add(get_key("日程数据", "events"), "从[日程数据]取值: events")
add(set_var("事件列表"), "存为变量 [事件列表]")
add(act(A["count"], {"WFCountType": "Items", "WFInput": var_ref("事件列表")}),
    "统计 [事件列表] 的项目数")
add(set_var("数量"), "存为变量 [数量]")

add(act(A["text"], {"WFTextActionText": d_text(" ")}), "空文本 (摘要初始值)")
add(set_var("摘要"), "存为变量 [摘要]")

# ----------------------------------------------------------------------
# ⑥ 逐项写入系统日历
# ----------------------------------------------------------------------
gid = repeat_start("事件列表")
for key, var in [("title", "标题"), ("emoji", "事件emoji"),
                 ("startDate", "开始时间"), ("endDate", "结束时间"),
                 ("location", "地点"), ("notes", "备注")]:
    add(get_key("Repeat Item", key), f"取值: {key} → [{var}]")
    add(set_var(var), f"存为变量 [{var}]")

add(act(A["text"], {"WFTextActionText": d_text([
    ("var", "事件emoji"), ("lit", " "), ("var", "标题"),
])}), "拼接标题: [事件emoji] [标题]")
add(set_var("完整标题"), "存为变量 [完整标题]")

add(act(A["add_event"], {
    "WFEventTitle": d_text([("var", "完整标题")]),
    "WFEventStartDate": d_text([("var", "开始时间")]),
    "WFEventEndDate": d_text([("var", "结束时间")]),
    "WFEventCalendar": d_text([("var", "目标日历")]),
    "WFEventLocation": d_text([("var", "地点")]),
    "WFEventNotes": d_text([("var", "备注")]),
    "WFEventAlarm": d_text([("var", "提醒分钟")]),
    "WFEventAllDay": False,
}), "添加新日历日程 (标题/起止/日历/地点/备注/提醒)")

add(act(A["text"], {"WFTextActionText": d_text([
    ("var", "摘要"), ("lit", "• "), ("var", "完整标题"), ("lit", "\n"),
])}), "追加摘要行")
add(set_var("摘要"), "存为变量 [摘要]")
repeat_end(gid)

# ----------------------------------------------------------------------
# ⑦ 完成提示
# ----------------------------------------------------------------------
add(act(A["result"], {"WFTextActionText": d_text([
    ("lit", "✅ 已写入 "), ("var", "数量"), ("lit", " 个日程到系统日历：\n\n"),
    ("var", "摘要"),
])}), "显示结果: 写入数量 + 摘要")

# ======================================================================
# 组装 .shortcut (快捷指令工程文件)
# ======================================================================
assert not GROUP_STACK, f"构建结束时仍有未闭合的控制流组: {GROUP_STACK}"
workflow = {
    "WFWorkflowActions": actions,
    "WFWorkflowClientRelease": "3.0",
    "WFWorkflowClientVersion": "1300",
    "WFWorkflowIcon": {
        "WFWorkflowIconColorNumber": 5,
        "WFWorkflowIconGlyphNumber": 57522,
    },
    "WFWorkflowImportQuestions": [],
    "WFWorkflowInputContentItemClasses": [
        "WFStringContentItem",
    ],
    "WFWorkflowTypes": ["NCWidget", "ActionExtension", "WatchKit"],
}

out_path = HERE / "Orbit轨道日程助手.shortcut"
out_path.write_bytes(plistlib.dumps(workflow, fmt=plistlib.FMT_XML,
                                    sort_keys=False))
print(f"OK 已生成 {out_path.name}  (共 {len(actions)} 个动作)")

# ======================================================================
# 校验: 重新解析 + 控制流配对检查 + token 范围检查
# ======================================================================
parsed = plistlib.loads(out_path.read_bytes())
assert parsed["WFWorkflowActions"] == actions, "round-trip 不一致"

stack = []
errors = []
for i, a in enumerate(parsed["WFWorkflowActions"]):
    p = a["WFWorkflowActionParameters"]
    gid = p.get("GroupingIdentifier")
    mode = p.get("WFControlFlowMode")
    ident = a["WFWorkflowActionIdentifier"]
    if ident not in FLOW_IDENTIFIERS:
        continue
    # 语义: If(mode0=开始,1=否则,2=结束) 菜单(mode0=开始,2=下一项,1=结束)
    #       重复(mode0=开始,2=结束)
    if mode == 0:
        stack.append((ident, gid))
        continue
    if not stack:
        errors.append(f"动作{i}: 控制流标记出现在任何组开始之前")
        continue
    top_ident, top_gid = stack[-1]
    if top_gid != gid:
        errors.append(f"动作{i}: 标记 {ident.split('.')[-1]}/{gid[:8]} "
                      f"与当前组 {top_ident.split('.')[-1]}/{top_gid[:8]} 不匹配")
        continue
    closes = (ident == A["conditional"] and mode == 2) or \
             (ident == A["menu"] and mode == 1) or \
             (ident == A["repeat"] and mode == 2)
    if closes:
        stack.pop()
    # 其余 (if 的 else / 菜单的下一项) 只校验匹配, 不弹栈
if stack:
    errors.append(f"有 {len(stack)} 个控制流组未正确闭合")


def walk_tokens(node, path="root"):
    if isinstance(node, dict):
        if node.get("WFSerializationType") == "WFTextTokenString":
            s = node["Value"]["string"]
            total = len(s.encode("utf-16-le")) // 2
            for rng in node["Value"].get("attachmentsByRange", {}):
                start, ln = map(int, rng.strip("{}").split(","))
                if start + ln > total:
                    errors.append(f"{path}: 附件范围 {rng} 越界 (串长{total})")
        for k, v in node.items():
            walk_tokens(v, f"{path}.{k}")
    elif isinstance(node, list):
        for j, v in enumerate(node):
            walk_tokens(v, f"{path}[{j}]")


walk_tokens(parsed)
if errors:
    print("!! 校验发现问题:")
    for e in errors:
        print("  -", e)
    raise SystemExit(1)
print("OK 校验通过: 控制流配对完整, 变量附件范围合法")

# ======================================================================
# 人类可读源码速览
# ======================================================================
lines = [
    "# Orbit·轨道 日程助手 —— 快捷指令源码速览",
    "",
    "> 由 `build_shortcut.py` 生成。此文件是《Orbit轨道日程助手.shortcut》的",
    "> 人类可读对照版：按执行顺序列出全部动作，供检查、教学与手动复刻使用。",
    "",
    f"动作总数：**{len(actions)}**　｜　生成目标：`Orbit轨道日程助手.shortcut`",
    "",
    "| # | 动作 | 说明 |",
    "|---|------|------|",
]
for i, (name, desc) in enumerate(flow_log, 1):
    safe = desc.replace("|", "\\|")
    lines.append(f"| {i} | {name} | {safe} |")
lines += [
    "",
    "## 需要在 iPhone 上人工确认的两处",
    "",
    "1. **请求体变量**：「获取 URL 内容」的请求体(JSON)字段指向变量 `请求体`。",
    "    若导入后该字段显示为空，请在编辑器中点开该字段，用魔术变量选择 `请求体`。",
    "2. **日历提醒**：「添加新日程」的提醒字段填了变量 `提醒分钟`，若导入后",
    "    丢失，请长按提醒字段重新选择变量 `提醒分钟`。",
    "",
]
(HERE / "源码速览.md").write_text("\n".join(lines), encoding="utf-8")
print("OK 已生成 源码速览.md")
