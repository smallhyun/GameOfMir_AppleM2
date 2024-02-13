unit EDcode;

interface

uses
  SysUtils, Grobal2;
const
  OLDMODE = 0;
  NEWMODE = 1;
  ENDECODEMODE = OLDMODE;


function EncodeMessage(smsg: TDefaultMessage): string;
function DecodeMessage(str: string): TDefaultMessage;
function EncodeString(str: string): string;
function DecodeString(str: string): string;
function EncodeBuffer(Buf: PAnsiChar; bufsize: Integer): string;
procedure DecodeBuffer(Src: string; Buf: PAnsiChar; bufsize: Integer);
procedure Decode6BitBuf(sSource: PAnsiChar; pbuf: PAnsiChar; nSrcLen, nBufLen: Integer);
procedure Encode6BitBuf(pSrc, PDest: PAnsiChar; nSrcLen, nDestLen: Integer);
function MakeDefaultMsg(wIdent: Word; nRecog: Integer; WParam, wTag, wSeries: Word): TDefaultMessage;
function EncodeLongBuffer(Buf: PAnsiChar; bufsize: Integer): string;
procedure DecodeLongBuffer(Src: string; Buf: PAnsiChar; bufsize: Integer);

var
  RSADECODESTRING2: string = '_DqDNXi';

implementation

{$IF ENDECODEMODE = NEWMODE}
CONST

  BITMASKS = $AA;

{$IFEND}

function MakeDefaultMsg(wIdent: Word; nRecog: Integer; WParam, wTag, wSeries:
  Word): TDefaultMessage;
begin
  Result.Recog := nRecog;
  Result.ident := wIdent;
  Result.param := WParam;
  Result.tag := wTag;
  Result.series := wSeries;
end;

procedure Encode6BitBuf(pSrc, PDest: PAnsiChar; nSrcLen, nDestLen: Integer);
var
  i: Integer;
  nRestCount: Integer;
  nDestPos: Integer;
  btMade: byte;
  btCh: byte;
  btRest: byte;
  btXor: Byte;
begin
  nRestCount := 0;
  btRest := 0;
  nDestPos := 0;
  for i := 0 to nSrcLen - 1 do
  begin
    if nDestPos >= nDestLen then
      break;
    btCh := byte(pSrc[i]);
{$IF ENDECODEMODE = NEWMODE}
    btXor := BITMASKS;
    Inc(btXor, i);
    btCh := btCh xor btXor;
{$IFEND}
    btMade := byte((btRest or (btCh shr (2 + nRestCount))) and $3F);
    btRest := byte(((btCh shl (8 - (2 + nRestCount))) shr 2) and $3F);
    Inc(nRestCount, 2);

    if nRestCount < 6 then
    begin
      PDest[nDestPos] := AnsiChar(btMade + $3C);
      Inc(nDestPos);
    end
    else
    begin
      if nDestPos < nDestLen - 1 then
      begin
        PDest[nDestPos] := AnsiChar(btMade + $3C);
        PDest[nDestPos + 1] := AnsiChar(btRest + $3C);
        Inc(nDestPos, 2);
      end
      else
      begin
        PDest[nDestPos] := AnsiChar(btMade + $3C);
        Inc(nDestPos);
      end;
      nRestCount := 0;
      btRest := 0;
    end;
  end;
  if nRestCount > 0 then
  begin
    PDest[nDestPos] := AnsiChar(btRest + $3C);
    Inc(nDestPos);
  end;
  PDest[nDestPos] := #0;
end;

procedure Decode6BitBuf(sSource: PAnsiChar; pbuf: PAnsiChar; nSrcLen, nBufLen: Integer);
const
  Masks: array[2..6] of byte = ($FC, $F8, $F0, $E0, $C0);
var
  i, nBitPos, nMadeBit, nBufPos: Integer;
  btCh, btTmp, btByte, btXor: byte;
begin
  nBitPos := 2;
  nMadeBit := 0;
  nBufPos := 0;
  btTmp := 0;
  btCh := 0;
  for i := 0 to nSrcLen - 1 do
  begin
    if Integer(sSource[i]) - $3C >= 0 then
      btCh := byte(sSource[i]) - $3C
    else
    begin
      nBufPos := 0;
      break;
    end;
    if nBufPos >= nBufLen then
      break;
    if (nMadeBit + 6) >= 8 then
    begin
      btByte := byte(btTmp or ((btCh and $3F) shr (6 - nBitPos)));
{$IF ENDECODEMODE = NEWMODE}
      btXor := BITMASKS;
      Inc(btXor, nBufPos);
      btByte := btByte xor btXor;
{$IFEND}
      pbuf[nBufPos] := AnsiChar(btByte);
      Inc(nBufPos);
      nMadeBit := 0;
      if nBitPos < 6 then
        Inc(nBitPos, 2)
      else
      begin
        nBitPos := 2;
        continue;
      end;
    end;
    btTmp := byte(byte(btCh shl nBitPos) and Masks[nBitPos]);
    Inc(nMadeBit, 8 - nBitPos);
  end;
  pbuf[nBufPos] := #0;
end;

function DecodeMessage(str: string): TDefaultMessage;
var
  EncBuf: array[0..BUFFERSIZE - 1] of AnsiChar;
  Msg: TDefaultMessage;
begin
  Decode6BitBuf(PAnsiChar(AnsiString(Str)), @EncBuf, Length(AnsiString(Str)), sizeof(EncBuf));
  Move(EncBuf, Msg, sizeof(TDefaultMessage));
  Result := Msg;
end;

function DecodeString(str: string): string;
var
  EncBuf: array[0..BUFFERSIZE - 1] of AnsiChar;
begin
  Decode6BitBuf(PAnsiChar(AnsiString(Str)), @EncBuf, Length(AnsiString(Str)), sizeof(EncBuf));
  Result := string(EncBuf);
end;

procedure DecodeBuffer(Src: string; Buf: PAnsiChar; bufsize: Integer);
var
  EncBuf: array[0..BUFFERSIZE - 1] of AnsiChar;
begin
  Decode6BitBuf(PAnsiChar(AnsiString(Src)), @EncBuf, Length(AnsiString(Src)), sizeof(EncBuf));
  Move(EncBuf, Buf^, bufsize);
end;

function EncodeMessage(smsg: TDefaultMessage): string;
var
  EncBuf, TempBuf: array[0..BUFFERSIZE - 1] of AnsiChar;
begin
  Move(smsg, TempBuf, sizeof(TDefaultMessage));
  Encode6BitBuf(@TempBuf, @EncBuf, sizeof(TDefaultMessage), sizeof(EncBuf));
  Result := string(EncBuf);
end;

function EncodeString(str: string): string;
var
  EncBuf: array[0..BUFFERSIZE - 1] of AnsiChar;
begin
  Encode6BitBuf(PAnsiChar(AnsiString(Str)), @EncBuf, Length(AnsiString(Str)), sizeof(EncBuf));
  Result := string(EncBuf);
end;

function EncodeBuffer(Buf: PAnsiChar; bufsize: Integer): string;
var
  EncBuf, TempBuf: array[0..BUFFERSIZE - 1] of AnsiChar;
begin
  if bufsize < BUFFERSIZE then
  begin
    Move(Buf^, TempBuf, bufsize);
    Encode6BitBuf(@TempBuf, @EncBuf, bufsize, sizeof(EncBuf));
    Result := string(EncBuf);
  end
  else
    Result := '';
end;



procedure DecodeLongBuffer(Src: string; Buf: PAnsiChar; bufsize: Integer);
  function GetCodeMsgSize(x: Double): Integer;
  begin
    if INT(x) < x then Result := Trunc(x) + 1
    else Result := Trunc(x);
  end;
var
  MaxLen: Integer;
  TextLen: Integer;
  WhiteLen: Integer;
  CStr: string;
begin
  MaxLen := GetCodeMsgSize(DATABUFFERSIZE * 4 / 3);
  TextLen := Length(Src);
  if TextLen > MaxLen then begin
    WhiteLen := 0;
    while (TextLen >= MaxLen) and (bufsize >= DATABUFFERSIZE) do begin
      CStr := Copy(Src, 1, MaxLen);
      Src := Copy(Src, MaxLen + 1, TextLen);
      Dec(TextLen, MaxLen);
      DecodeBuffer(CStr, @Buf[WhiteLen], DATABUFFERSIZE);
      Inc(WhiteLen, DATABUFFERSIZE);
      Dec(bufsize, DATABUFFERSIZE);
    end;
    if (bufsize > 0) and (TextLen > 0) and (Src <> '') then begin
      DecodeBuffer(Src, @Buf[WhiteLen], bufsize);
    end;
  end else begin
    DecodeBuffer(Src, Buf, BufSize);
  end;
end;

function EncodeLongBuffer(Buf: PAnsiChar; bufsize: Integer): string;
var
  WhiteLen: Integer;
begin
  Result := '';
  if bufsize > DATABUFFERSIZE then begin
    WhiteLen := 0;
    while (bufsize > DATABUFFERSIZE) do begin
      Result := Result + EncodeBuffer(@Buf[WhiteLen], DATABUFFERSIZE);
      Inc(WhiteLen, DATABUFFERSIZE);
      Dec(bufsize, DATABUFFERSIZE);
    end;
    if bufsize > 0 then
      Result := Result + EncodeBuffer(@Buf[WhiteLen], bufsize);
  end else begin
    Result := EncodeBuffer(Buf, bufsize);
  end;
end;

initialization
  begin
  end;

finalization
  begin
  end;
end.
