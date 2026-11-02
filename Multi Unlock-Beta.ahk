#SingleInstance Force
#NoEnv
CoordMode, Mouse, Screen
DetectHiddenWindows, On
iniFile := A_ScriptDir "\slotRect.ini"
slotCount := 0
captureActive := 0
captureIdx := 0
capX1 := 0, capY1 := 0
isSetupWizardActive := false
inputCooldownUntil := 0
wsCooldownUntil := 0

if (!A_IsAdmin) {
    Run *RunAs "%A_AhkPath%" "%A_ScriptFullPath%"
    ExitApp
}
if (!FileExist(iniFile)) {
    GoSub, SetupWizard
} else {
    GoSub, LoadSlots
}
SetTimer, WpStateMonitor, 500  ;每500ms轮询wpstateout检测
return
; API 挂起进程
SuspendProcess(pid) {
    hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "Int", pid)
    if (hProcess) {
        DllCall("ntdll.dll\NtSuspendProcess", "Int", hProcess)
        DllCall("CloseHandle", "Int", hProcess)
    }
}
; API 恢复被挂起进程
ResumeProcess(pid) {
    hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "Int", pid)
    if (hProcess) {
        DllCall("ntdll.dll\NtResumeProcess", "Int", hProcess)
        DllCall("CloseHandle", "Int", hProcess)
    }
}
; wpstateout轮询监控子程序
WpStateMonitor:
if(isSetupWizardActive || slotCount <=0)
    return
Loop, %slotCount% {
    i := A_Index
    wpPath := slotInstanceDir%i% "\wpstateout.txt"
    frozenFlag := slotInstanceDir%i% "\frozenflag"
    unlockedFlag := slotInstanceDir%i% "\unlockedflag"
    modTxt := slotTxt%i%

    if(!FileExist(wpPath) || !FileExist(modTxt))
        continue

    FileRead, modContent, %modTxt%
    if(!RegExMatch(modContent,"pid=(\d+)",pidMatch))
        continue
    targetPid := pidMatch1

    Process, Exist, %targetPid%
    if (!ErrorLevel)
        continue

    FileGetTime, wpModifyTime, %wpPath%, M
    EnvSub, wpModifyTime, A_Now, MS
    if (wpModifyTime < -1500)
        continue

    FileRead, wpContent, %wpPath%

    if (wpContent = "waiting") {
        if(FileExist(frozenFlag))
            FileDelete, %frozenFlag%
        if(FileExist(unlockedFlag))
            FileDelete, %unlockedFlag%
        continue
    }

    if(FileExist(unlockedFlag))
        continue

    if(!RegExMatch(wpContent,"generating,(\d+)",genMatch))
        continue
    genVal := genMatch1

    if(genVal > 3)
    {
        if (!FileExist(frozenFlag))
        {
            SuspendProcess(targetPid)
            FileOpen(frozenFlag, "w").Close()
        }
    }
}
return

; 判断OBS投影前台
IsOBSProjectionForeground() {
    WinGetTitle, activeWinTitle, A
    if (InStr(activeWinTitle, "Projector - Scene: Walling")) {
        return true
    }
    return false
}
SetupWizard:
isSetupWizardActive := true
slotCount := 0
InputBox, slotCount, 批量数量, 请输入Julti开多少实例：
if (ErrorLevel || slotCount = "" || !RegExMatch(slotCount, "^\d+$")) {
    MsgBox, 输入无效，退出
    ExitApp
}
GoSub, ClearOldSlotEntries
IniWrite, %slotCount%, %iniFile%, Main, SlotCount
txtArr := Object()
rectArr := Object()
Loop, %slotCount% {
    i := A_Index
    ; ==========【修改此处】不再输入txt完整路径，输入实例的.minecraft目录 ==========
    InputBox, instanceDirPath, 输入实例%i%的.minecraft实例目录, `n示例：E:\MultiMC\instances\RSG 1\.minecraft`n请粘贴该实例的 .minecraft 文件夹完整路径：
    if (ErrorLevel || instanceDirPath = "") {
        MsgBox, 取消输入，脚本退出
        ExitApp
    }
    txtArr[i] := instanceDirPath  ;存的是目录，不是txt文件
    IniWrite, %instanceDirPath%, %iniFile%, Slot%i%, InstanceDir
}
MsgBox, 全部实例目录录入完成！`n接下来开始依次框选预览窗口矩形。
captureIdx := 1
Goto, CaptureRectLoop
CaptureRectLoop:
if (captureIdx > slotCount)
{
    GoSub, SetupSave
    return
}
pendingTxtPath := txtArr[captureIdx]
MsgBox, 实例%captureIdx%：请框选预览窗口矩形`n鼠标放到左上角，左键点一下
captureActive := 1
capX1 := ""
return
SetupSave:
Loop, %slotCount% {
    i := A_Index
    r := rectArr[i]
    valX1 := r.x1
    valY1 := r.y1
    valX2 := r.x2
    valY2 := r.y2
    IniWrite, %valX1%, %iniFile%, Slot%i%, X1
    IniWrite, %valY1%, %iniFile%, Slot%i%, Y1
    IniWrite, %valX2%, %iniFile%, Slot%i%, X2
    IniWrite, %valY2%, %iniFile%, Slot%i%, Y2
}
MsgBox, 全部矩形注册完成，配置已保存
captureActive := 0
isSetupWizardActive := false
captureIdx := 0
txtArr := ""
rectArr := ""
GoSub, LoadSlots
return
ClearOldSlotEntries:
if (!FileExist(iniFile))
    return
FileRead, iniContent, %iniFile%
iniContent := RegExReplace(iniContent, "(\R|^)\[Slot\d+\](.*?)(?=\R\[[^\]]+\]|\z)", "", All)
f := FileOpen(iniFile, "w")
f.RawWrite(iniContent)
f.Close()
return
LoadSlots:
slotCount := 0
IniRead, slotCount, %iniFile%, Main, SlotCount, 0
if (slotCount <= 0)
    return
Loop, %slotCount% {
    i := A_Index
    ; =========【修改】读取键改为 InstanceDir，保存的是.minecraft目录，兼容旧配置TxtFile=========
    IniRead, slotInstanceDir%i%, %iniFile%, Slot%i%, InstanceDir
    if (slotInstanceDir%i% = "")
    {
        IniRead, slotInstanceDir%i%, %iniFile%, Slot%i%, TxtFile
    }
    IniRead, slotX1%i%, %iniFile%, Slot%i%, X1
    IniRead, slotY1%i%, %iniFile%, Slot%i%, Y1
    IniRead, slotX2%i%, %iniFile%, Slot%i%, X2
    IniRead, slotY2%i%, %iniFile%, Slot%i%, Y2
    ; 内部拼接得到modstateout.txt完整路径，向后兼容原有全部逻辑
    slotTxt%i% := slotInstanceDir%i% "\modstateout.txt"
}
return
~LButton::
; 左键完全不加任何冷却，原样保留原版全部逻辑
if (captureActive) {
    if (capX1 = "") {
        MouseGetPos, capX1, capY1
        MsgBox, 左上角已记录，放到窗口右下角再点左键
        return
    }
    MouseGetPos, capX2, capY2
    rx1 := Min(capX1, capX2)
    ry1 := Min(capY1, capY2)
    rx2 := Max(capX1, capX2)
    ry2 := Max(capY1, capY2)
    rectArr[captureIdx] := {x1:rx1, y1:ry1, x2:rx2, y2:ry2}
    capX1 := ""
    captureIdx += 1
    Goto, CaptureRectLoop
}
if (isSetupWizardActive)
    return
if (!IsOBSProjectionForeground())
    return
MouseGetPos, mx, my
hitTxt := ""
Loop, %slotCount% {
    i := A_Index
    x1 := slotX1%i%
    y1 := slotY1%i%
    x2 := slotX2%i%
    y2 := slotY2%i%
    if (mx >= x1 && mx <= x2 && my >= y1 && my <= y2) {
        hitTxt := slotTxt%i%
        break
    }
}
if (hitTxt = "" || !FileExist(hitTxt))
{
    return
}
SplitPath, hitTxt, , instanceDir
lockedFile := instanceDir "\locked"
if (!FileExist(lockedFile)) {
    f := FileOpen(lockedFile, "w")
    f.Close()
}
return
~E::
if (isSetupWizardActive)
    return
; E不使用冷却，直接执行
; 仅OBS投影前台才生效
if (!IsOBSProjectionForeground())
    return
MouseGetPos, mx, my
hitIndex := 0
hitTxt := ""
Loop, %slotCount% {
    i := A_Index
    x1 := slotX1%i%
    y1 := slotY1%i%
    x2 := slotX2%i%
    y2 := slotY2%i%
    if (mx >= x1 && mx <= x2 && my >= y1 && my <= y2) {
        hitIndex := i
        hitTxt := slotTxt%i%
        break
    }
}
; 鼠标不在任何slot框，直接无动作返回
if (hitIndex = 0 || hitTxt = "" || !FileExist(hitTxt))
    return
SplitPath, hitTxt, , instanceDir
lockedFile := instanceDir "\locked"
if (FileExist(lockedFile)) {
    FileDelete, %lockedFile%
}
return
~Space::
if (isSetupWizardActive)
    return
; =========增加3秒冷却=========
if (A_TickCount < wsCooldownUntil)
    return
wsCooldownUntil := A_TickCount + 3000
; W无冷却
; 获取当前前台窗口PID
WinGet, forePid, PID, A
if (!forePid)
    return
; 检查前台进程是不是java/javaw
WinGet, procName, ProcessName, ahk_pid %forePid%
if (procName != "javaw.exe" && procName != "java.exe")
    return
; 遍历slot，寻找modstateout.txt内pid等于前台pid的实例
foundTxt := ""
Loop, %slotCount% {
    i := A_Index
    txtPath := slotTxt%i%
    if (!FileExist(txtPath))
        continue
    FileRead, content, %txtPath%
    if RegExMatch(content, "pid=(\d+)", m) {
        slotPid := m1
        if (slotPid == forePid) {
            foundTxt := txtPath
            break
        }
    }
}
; 没找到匹配实例直接退出
if (foundTxt = "")
    return
; 删除该前台实例的locked，其余slot完全不动
SplitPath, foundTxt, , instanceDir
lockedFile := instanceDir "\locked"
if (FileExist(lockedFile)) {
    FileDelete, %lockedFile%
}
return
~W::
if (isSetupWizardActive)
    return
; =========增加3秒冷却=========
if (A_TickCount < wsCooldownUntil)
    return
wsCooldownUntil := A_TickCount + 3000
; W无冷却
; 获取当前前台窗口PID
WinGet, forePid, PID, A
if (!forePid)
    return
; 检查前台进程是不是java/javaw
WinGet, procName, ProcessName, ahk_pid %forePid%
if (procName != "javaw.exe" && procName != "java.exe")
    return
; 遍历slot，寻找modstateout.txt内pid等于前台pid的实例
foundTxt := ""
Loop, %slotCount% {
    i := A_Index
    txtPath := slotTxt%i%
    if (!FileExist(txtPath))
        continue
    FileRead, content, %txtPath%
    if RegExMatch(content, "pid=(\d+)", m) {
        slotPid := m1
        if (slotPid == forePid) {
            foundTxt := txtPath
            break
        }
    }
}
; 没找到匹配实例直接退出
if (foundTxt = "")
    return
; 删除该前台实例的locked，其余slot完全不动
SplitPath, foundTxt, , instanceDir
lockedFile := instanceDir "\locked"
if (FileExist(lockedFile)) {
    FileDelete, %lockedFile%
}
return
~T::
if (isSetupWizardActive)
    return
if (A_TickCount < inputCooldownUntil)
    return
inputCooldownUntil := A_TickCount + 1000
if (!IsOBSProjectionForeground())
    return
pidArr := Object()
objWMIService := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
colProcess := objWMIService.ExecQuery("Select ProcessId,Name from Win32_Process Where Name='javaw.exe' or Name='java.exe'")
for proc in colProcess {
    pidArr.Push(proc.ProcessId)
}
for _, pid in pidArr {
    ResumeProcess(pid)
}
Loop, %slotCount%
{
    i := A_Index
    frozenPath := slotInstanceDir%i% "\frozenflag"
    unlockedPath := slotInstanceDir%i% "\unlockedflag"
    if(FileExist(frozenPath))
        FileDelete, %frozenPath%
    ; 新增：打上放行标记，本轮不再重新冻
    FileOpen(unlockedPath, "w").Close()
}
Sleep, 1000
Loop, %slotCount%
{
    i := A_Index
    txtPath := slotTxt%i%
    if (!FileExist(txtPath))
        continue
    SplitPath, txtPath, , instanceDir
    lockedFile := instanceDir "\locked"
    if (FileExist(lockedFile))
        continue
    FileRead, c, %txtPath%
    if (!RegExMatch(c, "pid=(\d+)", m))
        continue
    targetPid := m1
    WinGet, hwndList, List, ahk_pid %targetPid%
    count := hwndList
    Loop, %count% {
        h := hwndList%A_Index%
        ControlSend,, {F6}, ahk_id %h%
    }
}
return
~F9::
if (isSetupWizardActive)
    return
; 1秒共享冷却
if (A_TickCount < inputCooldownUntil)
    return
inputCooldownUntil := A_TickCount + 1000
Loop, %slotCount% {
    i := A_Index
    txtPath := slotTxt%i%
    if (!FileExist(txtPath))
        continue
    SplitPath, txtPath, , instanceDir
    lockedFile := instanceDir "\locked"
    if (FileExist(lockedFile)) {
        FileDelete, %lockedFile%
    }
}
return
~RControl::
if(isSetupWizardActive)
    return

Loop, %slotCount%
{
    i := A_Index
    modTxt := slotTxt%i%
    slotDir := slotInstanceDir%i%

    if(!FileExist(modTxt))
        continue
    FileRead, modContent, %modTxt%
    if(!RegExMatch(modContent,"pid=(\d+)",pidMatch))
        continue
    targetPid := pidMatch1

    Process, Exist, %targetPid%
    if (!ErrorLevel)
        continue

    ; 解冻该槽位实例
    %ResumeProcess%(targetPid)
    Sleep, 80

    ; 打放行标记，关闭过程WpStateMonitor禁止再次冻结
    unlockedFlag := slotDir "\unlockedflag"
    f := FileOpen(unlockedFlag, "w")
    f.Close()
    f := ""
}
Sleep, 250

Loop, %slotCount%
{
    i := A_Index
    modTxt := slotTxt%i%
    if(!FileExist(modTxt))
        continue
    FileRead, modContent, %modTxt%
    if(!RegExMatch(modContent,"pid=(\d+)",pidMatch))
        continue
    targetPid := pidMatch1

    Process, Exist, %targetPid%
    if (!ErrorLevel)
        continue

    WinGet, hwndList, List, ahk_pid %targetPid%
    count := hwndList
    Loop, %count%
    {
        h := hwndList%A_Index%
        WinClose, ahk_id %h%
    }
}
Sleep, 800

Loop, %slotCount%
{
    i := A_Index
    modTxt := slotTxt%i%
    if(!FileExist(modTxt))
        continue
    FileRead, modContent, %modTxt%
    if(!RegExMatch(modContent,"pid=(\d+)",pidMatch))
        continue
    targetPid := pidMatch1

    Process, Exist, %targetPid%
    if (!ErrorLevel)
        continue

    WinKill, ahk_pid %targetPid%
}
Sleep, 300

Loop, %slotCount%
{
    i := A_Index
    slotDir := slotInstanceDir%i%
    wpPath := slotDir "\wpstateout.txt"

    ; 改用Write，写入waiting，覆盖原有内容
    f := FileOpen(wpPath, "w")
    if(f){
        f.Write("waiting")
        f.Close()
    }

    lockedFile := slotDir "\locked"
    frozenFlag := slotDir "\frozenflag"
    unlockedFlag := slotDir "\unlockedflag"

    if(FileExist(lockedFile))
        FileDelete, %lockedFile%
    if(FileExist(frozenFlag))
        FileDelete, %frozenFlag%
    if(FileExist(unlockedFlag))
        FileDelete, %unlockedFlag%
}

return