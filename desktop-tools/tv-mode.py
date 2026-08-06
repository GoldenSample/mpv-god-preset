# Кнопки режимов: панель ПК + профиль ТВ по хэндоффу одной командой.
# tv-mode.py cinema8k60 | cinema8k24 | cinema4k120 | desktop165 | pcinput
#
# ЗАКОН (07-22): панель Tizen сама закрывается по таймеру ~20-30с. Все дорожки
# ниже - КОРОТКИЕ и БЕЗ пауз на раздумья, укладываются в таймер с запасом.
# KEY_EXIT НЕ ИСПОЛЬЗОВАТЬ - выкидывает на Home/Art Store. Только KEY_RETURN.
#
# Подтверждено камерой 07-22 на 8K@60 (список = сигнал-зависимый, порядок
# может отличаться на других разрешениях, но структура floor->count работает):
#   Реж.изображения: Динамический/Стандартный/Эко/Кино/FILMMAKER MODE (5 шт)
#   floor-bottom (DOWN x12) = FILMMAKER MODE
#   Стандартный = floor-bottom + UP x3
#   Местное затемнение (Advanced): floor-bottom (DOWN x22) + UP x7
import ssl, json, base64, time, subprocess, sys

TV_IP = "192.168.1.65"
TOKEN_FILE = r"C:\Users\Administrator\AppData\Local\laplace-sandbox\secrets\TIZEN_WS_TOKEN.txt"
SETDISPLAY = r"C:\Apps\display-mode\SetDisplay.exe"


def remote():
    import websocket
    tok = open(TOKEN_FILE).read().strip()
    name = base64.b64encode(b"ClaudeTV").decode()
    url = f"wss://{TV_IP}:8002/api/v2/channels/samsung.remote.control?name={name}&token={tok}"
    ws = websocket.create_connection(url, timeout=10, sslopt={"cert_reqs": ssl.CERT_NONE})
    json.loads(ws.recv())
    return ws


def key(ws, k, pause=0.35):
    ws.send(json.dumps({"method": "ms.remote.control",
                        "params": {"Cmd": "Click", "DataOfCmd": k,
                                   "Option": "false", "TypeOfRemote": "SendRemoteKey"}}))
    time.sleep(pause)


def pc_input(ws):
    key(ws, "KEY_SOURCE", 1.6)
    key(ws, "KEY_ENTER", 1.6)


def set_picture_mode(ws, target):
    # target: "filmmaker" | "standard". Дорожка короткая, без пауз на снимки.
    key(ws, "KEY_MENU", 1.8)
    for _ in range(8):
        key(ws, "KEY_UP", 0.2)
    key(ws, "KEY_DOWN"); key(ws, "KEY_DOWN")
    key(ws, "KEY_ENTER", 1.2)      # Изображение
    key(ws, "KEY_ENTER", 1.2)      # Реж.изображения -> список
    for _ in range(12):
        key(ws, "KEY_DOWN", 0.2)   # floor-bottom = FILMMAKER MODE
    if target == "standard":
        for _ in range(3):
            key(ws, "KEY_UP", 0.25)
    key(ws, "KEY_ENTER", 1.0)      # выбрать
    for _ in range(4):             # список -> Изображение -> закрыть панель
        key(ws, "KEY_RETURN", 0.6) # (4 подтверждено камерой 07-22, меньше не хватает)


def set_local_dimming(ws, target):
    # target: "high" | "standard"
    key(ws, "KEY_MENU", 1.8)
    for _ in range(8):
        key(ws, "KEY_UP", 0.2)
    key(ws, "KEY_DOWN"); key(ws, "KEY_DOWN")
    key(ws, "KEY_ENTER", 1.2)      # Изображение
    for _ in range(3):
        key(ws, "KEY_DOWN")
    key(ws, "KEY_ENTER", 1.2)      # Дополнительные настройки
    for _ in range(22):
        key(ws, "KEY_DOWN", 0.2)   # floor-bottom
    for _ in range(7):
        key(ws, "KEY_UP", 0.25)    # -> Местное затемнение
    key(ws, "KEY_ENTER", 1.0)      # попап Низкий/Стандартный/Высокий
    for _ in range(3):
        key(ws, "KEY_DOWN", 0.25)  # floor попапа = Высокий
    if target == "standard":
        key(ws, "KEY_UP", 0.3)
    key(ws, "KEY_ENTER", 0.9)
    for _ in range(4):             # попап -> Доп.настройки -> Изображение -> закрыть
        key(ws, "KEY_RETURN", 0.6)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "pcinput"
    plan = {
        "cinema8k60": {"disp": ["7680", "4320", "60"], "dim": "high", "pic": "filmmaker"},
        "cinema8k24": {"disp": ["7680", "4320", "24"], "dim": "high", "pic": "filmmaker"},
        "desktop165": {"disp": ["3840", "2160", "165"], "dim": "standard", "pic": "standard"},
        # 4K120 - рабочая точка для кино С УПЛАВНЕНИЕМ (замер 08-06):
        #   120/3 = 40 -> RIFE даёт ровно 40 fps, лок каденции целый;
        #   на 165 Гц кап выдаёт 41.2 (дробный лок), на 24 Гц RIFE не нужен;
        #   120 Гц НЕ уводит телевизор в режим PC (граница выше 120), значит
        #   FILMMAKER и Movie остаются доступны, в отличие от 144/165.
        # dim/pic НЕ трогаем: слепые тыки по меню промахиваются с тех пор, как
        # калибровка добавила в список пункт "Кино (откалиброванный)".
        "cinema4k120": {"disp": ["3840", "2160", "120"], "dim": None, "pic": None},
        "pcinput":    {"disp": None, "dim": None, "pic": None},
    }[mode]

    if plan["disp"]:
        subprocess.run([SETDISPLAY] + plan["disp"], timeout=30)
        time.sleep(3)

    ws = remote()
    try:
        pc_input(ws)
        if plan["dim"]:
            set_local_dimming(ws, plan["dim"])
        if plan["pic"]:
            set_picture_mode(ws, plan["pic"])
    finally:
        ws.close()


if __name__ == "__main__":
    main()
