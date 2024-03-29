{*******************************************************}
{                                                       }
{       从内存中运行执行程序单元                        }
{                                                       }
{       版权所有 (C) 2009 Jason                         }
{                                                       }
{*******************************************************}

unit MemRun;

interface

uses windows;

function MemExecute(const ABuffer; Len: Integer; CmdParam: string; var ProcessInfo: TProcessInformation): Boolean;

implementation

type
  TImageSectionHeaders = array[0..0] of TImageSectionHeader;
  PImageSectionHeaders = ^TImageSectionHeaders;

  { 计算对齐后的大小 }

function GetAlignedSize(Origin, Alignment: Cardinal): Cardinal;
begin
  result := (Origin + Alignment - 1) div Alignment * Alignment;
end;

{ 计算加载pe并对齐需要占用多少内存，未直接使用OptionalHeader.SizeOfImage作为结果是因为据说有的编译器生成的exe这个值会填0 }

function CalcTotalImageSize(MzH: PImageDosHeader; FileLen: Cardinal; peH: PImageNtHeaders; peSecH: PImageSectionHeaders):
  Cardinal;
var
  i: Integer;
begin
  {计算pe头的大小}
  result := GetAlignedSize(PeH.OptionalHeader.SizeOfHeaders, PeH.OptionalHeader.SectionAlignment);

  {计算所有节的大小}
  for i := 0 to peH.FileHeader.NumberOfSections - 1 do
    if peSecH[i].PointerToRawData + peSecH[i].SizeOfRawData > FileLen then begin {// 超出文件范围}
      result := 0;
      exit;
    end
    else if peSecH[i].VirtualAddress <> 0 then //计算对齐后某节的大小
      if peSecH[i].Misc.VirtualSize <> 0 then
        result := GetAlignedSize(peSecH[i].VirtualAddress + peSecH[i].Misc.VirtualSize, PeH.OptionalHeader.SectionAlignment)
      else
        result := GetAlignedSize(peSecH[i].VirtualAddress + peSecH[i].SizeOfRawData, PeH.OptionalHeader.SectionAlignment)
    else if peSecH[i].Misc.VirtualSize < peSecH[i].SizeOfRawData then
      result := result + GetAlignedSize(peSecH[i].SizeOfRawData, peH.OptionalHeader.SectionAlignment)
    else
      result := result + GetAlignedSize(peSecH[i].Misc.VirtualSize, PeH.OptionalHeader.SectionAlignment);

end;

{ 加载pe到内存并对齐所有节 }
function AlignPEToMem(const Buf; Len: Integer; var PeH: PImageNtHeaders;
  var PeSecH: PImageSectionHeaders; var Mem: Pointer; var ImageSize: Cardinal): Boolean;
var
  SrcMz: PImageDosHeader; // DOS头
  SrcPeH: PImageNtHeaders; // PE头
  SrcPeSecH: PImageSectionHeaders; // 节表
  i: Integer;
  l: Cardinal;
  Pt: Pointer;
begin
  result := false;
  SrcMz := @Buf;
  if Len < sizeof(TImageDosHeader) then
    exit;
  if SrcMz.e_magic <> IMAGE_DOS_SIGNATURE then
    exit;
  if Len < SrcMz._lfanew + Sizeof(TImageNtHeaders) then
    exit;
  SrcPeH := pointer(Integer(SrcMz) + SrcMz._lfanew);
  if (SrcPeH.Signature <> IMAGE_NT_SIGNATURE) then
    exit;
  if (SrcPeH.FileHeader.Characteristics and IMAGE_FILE_DLL <> 0) or
    (SrcPeH.FileHeader.Characteristics and IMAGE_FILE_EXECUTABLE_IMAGE = 0)
    or (SrcPeH.FileHeader.SizeOfOptionalHeader <> SizeOf(TImageOptionalHeader)) then
    exit;
  SrcPeSecH := Pointer(Integer(SrcPeH) + SizeOf(TImageNtHeaders));
  ImageSize := CalcTotalImageSize(SrcMz, Len, SrcPeH, SrcPeSecH);
  if ImageSize = 0 then
    exit;
  Mem := VirtualAlloc(nil, ImageSize, MEM_COMMIT, PAGE_EXECUTE_READWRITE); // 分配内存
  if Mem <> nil then begin
    // 计算需要复制的PE头字节数
    l := SrcPeH.OptionalHeader.SizeOfHeaders;
    for i := 0 to SrcPeH.FileHeader.NumberOfSections - 1 do
      if (SrcPeSecH[i].PointerToRawData <> 0) and (SrcPeSecH[i].PointerToRawData < l) then
        l := SrcPeSecH[i].PointerToRawData;
    Move(SrcMz^, Mem^, l);
    PeH := Pointer(Integer(Mem) + PImageDosHeader(Mem)._lfanew);
    PeSecH := Pointer(Integer(PeH) + sizeof(TImageNtHeaders));

    Pt := Pointer(Cardinal(Mem) + GetAlignedSize(PeH.OptionalHeader.SizeOfHeaders, PeH.OptionalHeader.SectionAlignment));
    for i := 0 to PeH.FileHeader.NumberOfSections - 1 do begin
      // 定位该节在内存中的位置
      if PeSecH[i].VirtualAddress <> 0 then
        Pt := Pointer(Cardinal(Mem) + PeSecH[i].VirtualAddress);

      if PeSecH[i].SizeOfRawData <> 0 then begin
        // 复制数据到内存
        Move(Pointer(Cardinal(SrcMz) + PeSecH[i].PointerToRawData)^, pt^, PeSecH[i].SizeOfRawData);
        if peSecH[i].Misc.VirtualSize < peSecH[i].SizeOfRawData then
          pt := pointer(Cardinal(pt) + GetAlignedSize(PeSecH[i].SizeOfRawData, PeH.OptionalHeader.SectionAlignment))
        else
          pt := pointer(Cardinal(pt) + GetAlignedSize(peSecH[i].Misc.VirtualSize, peH.OptionalHeader.SectionAlignment));
        // pt 定位到下一节开始位置
      end
      else
        pt := pointer(Cardinal(pt) + GetAlignedSize(PeSecH[i].Misc.VirtualSize, PeH.OptionalHeader.SectionAlignment));
    end;
    result := True;
  end;
end;

type
  TVirtualAllocEx = function(hProcess: THandle; lpAddress: Pointer;
    dwSize, flAllocationType: DWORD; flProtect: DWORD): Pointer; stdcall;

var
  MyVirtualAllocEx: TVirtualAllocEx = nil;

function IsNT: Boolean;
begin
  result := Assigned(MyVirtualAllocEx);
end;

{ 是否包含可重定向列表 }

function HasRelocationTable(peH: PImageNtHeaders): Boolean;
begin
  result := (peH.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC].VirtualAddress <> 0)
    and (peH.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC].Size <> 0);
end;

type
  PImageBaseRelocation = ^TImageBaseRelocation;
  TImageBaseRelocation = packed record
    VirtualAddress: cardinal;
    SizeOfBlock: cardinal;
  end;

  { 重定向PE用到的地址 }

procedure DoRelocation(peH: PImageNtHeaders; OldBase, NewBase: Pointer);
var
  Delta: Cardinal;
  p: PImageBaseRelocation;
  pw: PWord;
  i: Integer;
begin
  Delta := Cardinal(NewBase) - peH.OptionalHeader.ImageBase;
  p := pointer(cardinal(OldBase) + peH.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC].VirtualAddress);
  while (p.VirtualAddress + p.SizeOfBlock <> 0) do begin
    pw := pointer(Integer(p) + Sizeof(p^));
    for i := 1 to (p.SizeOfBlock - Sizeof(p^)) div 2 do begin
      if pw^ and $F000 = $3000 then
        Inc(PCardinal(Cardinal(OldBase) + p.VirtualAddress + (pw^ and $0FFF))^, Delta);
      inc(pw);
    end;
    p := Pointer(pw);
  end;
end;

type
  TZwUnmapViewOfSection = function(Handle, BaseAdr: Cardinal): Cardinal; stdcall;

  { 卸载原外壳占用内存 }

function UnloadShell(ProcHnd, BaseAddr: Cardinal): Boolean;
var
  M: HModule;
  ZwUnmapViewOfSection: TZwUnmapViewOfSection;
begin
  result := False;
  m := LoadLibrary('ntdll.dll');
  if m <> 0 then begin
    ZwUnmapViewOfSection := GetProcAddress(m, 'ZwUnmapViewOfSection');
    if assigned(ZwUnmapViewOfSection) then
      result := (ZwUnmapViewOfSection(ProcHnd, BaseAddr) = 0);
    FreeLibrary(m);
  end;
end;

{ 创建外壳进程并获取其基址、大小和当前运行状态 }

function CreateChild(Cmd: string; var Ctx: TContext; var BaseAddr, ImageSize: Cardinal; var ProcessInfo: TProcessInformation): Boolean;
var
  si: TStartUpInfo;
  Old: NativeUInt;
  MemInfo: TMemoryBasicInformation;
  p: Pointer;
begin
  FillChar(si, Sizeof(si), 0);
  FillChar(ProcessInfo, SizeOf(ProcessInfo), 0);
  si.cb := sizeof(si);
  Result := CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_SUSPENDED, nil, nil, si, ProcessInfo); // 以挂起方式运行进程
  if Result then begin
    { 获取外壳进程运行状态，[ctx.Ebx+8]内存处存的是外壳进程的加载基址，ctx.Eax存放有外壳进程的入口地址 }
    ctx.ContextFlags := CONTEXT_FULL;
    GetThreadContext(ProcessInfo.hThread, ctx);
    ReadProcessMemory(ProcessInfo.hProcess, Pointer(ctx.Ebx + 8), @BaseAddr, SizeOf(Cardinal), Old); // 读取加载基址
    p := Pointer(BaseAddr);

    { 计算外壳进程占有的内存 }
    while VirtualQueryEx(ProcessInfo.hProcess, p, MemInfo, Sizeof(MemInfo)) <> 0 do begin
      if MemInfo.State = MEM_FREE then
        break;
      p := Pointer(Cardinal(p) + MemInfo.RegionSize);
    end;
    ImageSize := Cardinal(p) - Cardinal(BaseAddr);
  end;
end;

{ 创建外壳进程并用目标进程替换它然后执行 }

function AttachPE(CmdParam: string; peH: PImageNtHeaders; peSecH: PImageSectionHeaders;
  Ptr: Pointer; ImageSize: Cardinal; var ProcessInfo: TProcessInformation): Boolean;
var
  //s: string;
  Addr, Size: Cardinal;
  ctx: TContext;
  Old: NativeUInt;
  p: Pointer;
  OldP: Pointer;
begin
  Result := False;
  if CreateChild(CmdParam, ctx, Addr, Size, ProcessInfo) then begin
    p := nil;
    // 外壳进程可以容纳目标进程并且加载地址一致
    if (peH.OptionalHeader.ImageBase = Addr) and (Size >= ImageSize) then begin
      p := Pointer(Addr);
      OldP := Pointer(Old);
      VirtualProtectEx(ProcessInfo.hProcess, p, Size, PAGE_EXECUTE_READWRITE, OldP);
    end
    else if IsNT then begin  // 98 下失败
      if UnloadShell(ProcessInfo.hProcess, Addr) then // 卸载外壳进程占有内存
        // 重新按目标进程加载基址和大小分配内存
        p := MyVirtualAllocEx(ProcessInfo.hProcess, Pointer(peH.OptionalHeader.ImageBase), ImageSize, MEM_RESERVE or MEM_COMMIT,
          PAGE_EXECUTE_READWRITE);
    end;
    if p <> nil then begin
      WriteProcessMemory(ProcessInfo.hProcess, Pointer(ctx.Ebx + 8), @p, Sizeof(DWORD), Old); // 重置目标进程运行环境中的基址
      peH.OptionalHeader.ImageBase := Cardinal(p);
      if WriteProcessMemory(ProcessInfo.hProcess, p, Ptr, ImageSize, Old) then begin {// 复制PE数据到目标进程}
        ctx.ContextFlags := CONTEXT_FULL;
        if Cardinal(p) = Addr then
          ctx.Eax := peH.OptionalHeader.ImageBase + peH.OptionalHeader.AddressOfEntryPoint // 重置运行环境中的入口地址
        else
          ctx.Eax := Cardinal(p) + peH.OptionalHeader.AddressOfEntryPoint;
        SetThreadContext(ProcessInfo.hThread, ctx); // 更新运行环境
        ResumeThread(ProcessInfo.hThread); // 执行
        CloseHandle(ProcessInfo.hThread);
        Result := True;
      end
      else begin // 加载失败,杀掉外壳进程
        TerminateProcess(ProcessInfo.hProcess, 0);
        CloseHandle(ProcessInfo.hThread);
        CloseHandle(ProcessInfo.hProcess);
        ProcessInfo.hProcess := INVALID_HANDLE_VALUE;
      end;
    end
    else begin // 加载失败,杀掉外壳进程
      TerminateProcess(ProcessInfo.hProcess, 0);
      CloseHandle(ProcessInfo.hThread);
      CloseHandle(ProcessInfo.hProcess);
      ProcessInfo.hProcess := INVALID_HANDLE_VALUE;
    end;
  end;
end;

function MemExecute(const ABuffer; Len: Integer; CmdParam: string; var ProcessInfo: TProcessInformation): Boolean;
var
  peH: PImageNtHeaders;
  peSecH: PImageSectionHeaders;
  Ptr: Pointer;
  peSz: Cardinal;
begin
  Result := False;
  if (Len > 0) and AlignPEToMem(ABuffer, Len, peH, peSecH, Ptr, peSz) then begin
    Result := AttachPE(CmdParam, peH, peSecH, Ptr, peSz, ProcessInfo);
    VirtualFree(Ptr, peSz, MEM_DECOMMIT);
  end;
end;

initialization
  MyVirtualAllocEx := GetProcAddress(GetModuleHandle('Kernel32.dll'), 'VirtualAllocEx');

end.

