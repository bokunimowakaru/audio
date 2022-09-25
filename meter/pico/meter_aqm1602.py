###############################################################################
# Stereo Audio Peak Meter for Raspberry Pi Pico
###############################################################################
# キャラクタ液晶(LCD)にレベルメータ表示を行います
#
#                                              Copyright (c) 2022 Wataru KUNINO
###############################################################################

# ADC接続方法: 直流カットC=1u～10uFとプルアップ抵抗R=33kΩ経由で下記に接続する
##############################
# Audio   # Pico # GPIO (ADC)
##############################
#    Lch  #  31  # ADC0(GP26)
#    Rch  #  32  # ADC1(GP27)

# AE-AQM0802A, AE-AQM1602A, AQM1602Y 
##############################
# AQM1602 # Pico # GPIO
##############################
#     +V  #  5   # GP3
#    SDA  #  6   # GP4
#    SCL  #  7   # GP5
#    GND  #  8   # GND
##############################
# 参考文献1 LCD用I2C制御サンプル
# https://github.com/bokunimowakaru/RaspberryPi/blob/master/libs/soft_i2c.c
# Copyright (c) 2014-2017 Wataru KUNINO https://bokunimo.net/raspi/
#
# 参考文献2 Sitronix LCDコントローラST7032 データシート (2008/08/18)
# https://akizukidenshi.com/download/ds/sitronix/st7032.pdf

# Raspberry Pi Picoの消費電流
#  25 mA AQM1602Y-NLW-FBW(白色バックライト) バックライト 3.3V直ON
#  22 mA バックライトOFF

aqm1602 = 0x3E                          # LCD AQM1602のI2Cアドレス

from machine import ADC,Pin,PWM,I2C     # ライブラリmachineのADC等を組み込む
from utime import sleep                 # μtimeからsleepを組み込む
from math import log10                  # 対数変換用モジュールを組み込む

freq = 40000                            # AD変換周波数(Hz)
window = 1024                           # 1回あたりの計測サンプル数
display = 'AC'                          # メータ切り替え
dispAcMaxMv = 1000                      # AC入力電圧(mV)
dispAcRangeDb = 40                      # レベルメータ表示範囲(dB)
sample_wait = 1 / freq                  # 計測周期(Sec.)

vdd = Pin(3, Pin.OUT)                   # GP3をAQM1602のV+ピンに接続
vdd.value(1)                            # V+用に3.3Vを出力
i2c = I2C(0, scl=Pin(5), sda=Pin(4))    # GP5をAQM1602のSCL,GP4をSDAに接続
i2c.writeto_mem(aqm1602, 0x00, b'\x39') # LCD制御 IS=1
i2c.writeto_mem(aqm1602, 0x00, b'\x14') # LCD制御 OSC=4
i2c.writeto_mem(aqm1602, 0x00, b'\x73') # LCD制御 コントラスト  3
i2c.writeto_mem(aqm1602, 0x00, b'\x5E') # LCD制御 Power/Cont    E
i2c.writeto_mem(aqm1602, 0x00, b'\x6C') # LCD制御 FollowerCtrl  C
sleep(0.2);
i2c.writeto_mem(aqm1602, 0x00, b'\x38') # LCD制御 IS=0
i2c.writeto_mem(aqm1602, 0x00, b'\x0C') # LCD制御 DisplayON     C

# レベルメータ用フォント作成 0x00～0x02:点灯数
# 参考文献
# https://github.com/bokunimowakaru/xbeeCoord/tree/master/xbee_arduino/XBee_Coord/examples/sample11_lcd
# Copyright (c) 2013 Wataru KUNINO https://bokunimo.net/xbee/
font_lv = [
    b'\x00\x01\x00\x01\x00\x01\x00\x15',
    b'\x18\x19\x18\x19\x18\x19\x18\x15',
    b'\x1B\x1B\x1B\x1B\x1B\x1B\x1B\x15',
    b'\x03\x03\x03\x03\x03\x03\x03\x15'
]
for j in range(4):                      # LCD制御 フォントの転送
    i2c.writeto_mem(aqm1602, 0x00, bytes([0x40+j*8])) # CGRAM address 0x00～0x02
    i2c.writeto_mem(aqm1602, 0x40, font_lv[j]) # フォント

def calc_volt2db(volt):                 # dB電圧を0～32の表示尺で応答する
    i = int((20 * log10(volt/dispAcMaxMv) + dispAcRangeDb)/dispAcRangeDb * 32)
    if i < 0:
        i = 0
    if i > 32:
        i = 32
    return i

led = PWM(Pin(25, Pin.OUT))             # PWM出力用インスタンスledを生成
led.freq(60)
adc0 = ADC(0)                           # ADCポート0(Pin31)用adc0を生成
adc1 = ADC(1)                           # ADCポート1(Pin32)用adc1を生成

peak_i = 0
peakLv = [0, 0]
peakDb = [0, 0]
text = bytearray(16)
while True:                             # 繰り返し処理
    vals = [[],[]]
    valSum = [0, 0]
    valDc = [0, 0]
    valAc = [0, 0]
    voltDc = [0.0, 0.0]
    voltAc = [0.0, 0.0]
    for i in range(window):
        adc = adc0.read_u16()
        valSum[0] += adc
        vals[0].append(adc)             # ADCから値を取得して変数valに代入
        adc = adc1.read_u16()
        valSum[1] += adc
        vals[1].append(adc)             # ADCから値を取得して変数valに代入
        sleep(sample_wait)              # 待ち時間処理
    peak_i += 1
    for ch in range(2):
        valDc[ch] = int(valSum[ch] / window + 0.5)
        acSum = 0
        for i in range(window):
            acSum += abs(vals[ch][i] - valDc[ch])
        valAc[ch] = int(acSum / window + 0.5)
        voltDc[ch] = valDc[ch] * 3300 / 65535       # 直流分ADC値を電圧(mV)に変換
        voltAc[ch] = valAc[ch] * 3300 / 65535       # 交流分ADC値を電圧(mV)に変換
        if peak_i > 16:
            peakLv[ch] = voltAc[ch]
            if ch >= 1:
                peak_i = 0
        if peakLv[ch] < voltAc[ch]:
            peakLv[ch] = voltAc[ch]
            peakDb[ch] = calc_volt2db(voltAc[ch])
        if display == 'AC':
            level = calc_volt2db(voltAc[ch])
            if level < 0:
                level = 0
            if level > dispAcRangeDb:
                level = dispAcRangeDb
            for i in range(16):
                i22 = i * 2 + 1                 # セルの右側に相当するレベル値
                if i < level // 2:              # セル位置がレベル未満の時
                    text[i] = 0x02              # セルの両側を点灯
                elif i == level // 2:           # セル位置がレベル位置の時
                    if i22 == level or i22 == peakDb[ch]:   # セルの右までの時
                        text[i] = 0x02          # セルの両側を点灯
                    else:                       # (セルの左までの時)
                        text[i] = 0x01          # セルの左側を点灯
                elif i > 0 and i == peakDb[ch] // 2: # ピーク単独表示位置の時
                    if i22 == peakDb[ch]:       # ピーク位置が右側のとき
                        text[i] = 0x03          # セルの右側のみ単独点灯
                    else:                       # (ピーク位置が左側の時)
                        text[i] = 0x01          # セルの左側を点灯
                else:                           # 点灯条件に該当しないとき
                    text[i] = 0x00              # 非点灯表示
            if ch == 0:
                i2c.writeto_mem(aqm1602, 0x00, b'\x80')
            else:
                i2c.writeto_mem(aqm1602, 0x00, b'\xC0')
            i2c.writeto_mem(aqm1602, 0x40, text)
            print('Voltage AC =', voltAc[ch], 'Peak =', peakLv[ch], 'Level =', level)
    led.duty_u16((valAc[0]+valAc[1])//2)                   # LEDを点灯する
