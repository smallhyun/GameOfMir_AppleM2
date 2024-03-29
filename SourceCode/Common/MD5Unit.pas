unit MD5Unit;

interface

uses
  Windows, SysUtils, Classes;

const
  CRCPOLY = $EDB88320;

type
  TProgressEvent = procedure(aPercent: Integer) of object;

  MD5Count = array[0..1] of DWORD;
  MD5State = array[0..3] of DWORD;
  MD5Block = array[0..15] of DWORD;
  MD5CBits = array[0..7] of byte;
  MD5Digest = array[0..15] of byte;
  MD5Buffer = array[0..63] of byte;
  MD5Context = record
    State: MD5State;
    Count: MD5Count;
    Buffer: MD5Buffer;
  end;

  Long = record
    LoWord: Word;
    HiWord: Word;
  end;

procedure MD5Init(var Context: MD5Context);
procedure MD5Update(var Context: MD5Context; Input: PAnsiChar; Length: longword);
procedure MD5Result(var Context: MD5Context; var Digest: MD5Digest);
function GetMD5Text(Input: string): string;
function GetMD5TextOf16(Input: string): string;
function GetMD5TextByBuffer(Buffer: PAnsiChar; BuffLen: Integer): string;

function GetCRC32(FileName: string): LongInt;

function GetMD5OfFile(const aFileName: string; aProgress: TProgressEvent; nOffset: Integer = 0): MD5Digest;
function MD5Print(D: MD5Digest): string;

function FileToMD5Text(const sFileName: string): string;

implementation

var
  PADDING: MD5Buffer = (
    $80, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00
    );

  CRCTable: array[0..512] of Longint;

function F(x, y, z: DWORD): DWORD;
begin
  Result := (x and y) or ((not x) and z);
end;

function G(x, y, z: DWORD): DWORD;
begin
  Result := (x and z) or (y and (not z));
end;

function H(x, y, z: DWORD): DWORD;
begin
  Result := x xor y xor z;
end;

function I(x, y, z: DWORD): DWORD;
begin
  Result := y xor (x or (not z));
end;

procedure rot(var x: DWORD; n: BYTE);
begin
  x := (x shl n) or (x shr (32 - n));
end;

procedure FF(var a: DWORD; b, c, d, x: DWORD; s: BYTE; ac: DWORD);
begin
  inc(a, F(b, c, d) + x + ac);
  rot(a, s);
  inc(a, b);
end;

procedure GG(var a: DWORD; b, c, d, x: DWORD; s: BYTE; ac: DWORD);
begin
  inc(a, G(b, c, d) + x + ac);
  rot(a, s);
  inc(a, b);
end;

procedure HH(var a: DWORD; b, c, d, x: DWORD; s: BYTE; ac: DWORD);
begin
  inc(a, H(b, c, d) + x + ac);
  rot(a, s);
  inc(a, b);
end;

procedure II(var a: DWORD; b, c, d, x: DWORD; s: BYTE; ac: DWORD);
begin
  inc(a, I(b, c, d) + x + ac);
  rot(a, s);
  inc(a, b);
end;

procedure Encode(Source, Target: pointer; Count: longword);
var
  S: PByte;
  T: PDWORD;
  I: longword;
begin
  S := Source;
  T := Target;
  for I := 1 to Count div 4 do begin
    T^ := S^;
    inc(S);
    T^ := T^ or (S^ shl 8);
    inc(S);
    T^ := T^ or (S^ shl 16);
    inc(S);
    T^ := T^ or (S^ shl 24);
    inc(S);
    inc(T);
  end;
end;

procedure Decode(Source, Target: pointer; Count: longword);
var
  S: PDWORD;
  T: PByte;
  I: longword;
begin
  S := Source;
  T := Target;
  for I := 1 to Count do begin
    T^ := S^ and $FF;
    inc(T);
    T^ := (S^ shr 8) and $FF;
    inc(T);
    T^ := (S^ shr 16) and $FF;
    inc(T);
    T^ := (S^ shr 24) and $FF;
    inc(T);
    inc(S);
  end;
end;

procedure Transform(Buffer: pointer; var State: MD5State);
var
  a, b, c, d: DWORD;
  Block: MD5Block;
begin
  Encode(Buffer, @Block, 64);
  a := State[0];
  b := State[1];
  c := State[2];
  d := State[3];
  FF(a, b, c, d, Block[0], 7, $D76AA478);
  FF(d, a, b, c, Block[1], 12, $E8C7B756);
  FF(c, d, a, b, Block[2], 17, $242070DB);
  FF(b, c, d, a, Block[3], 22, $C1BDCEEE);
  FF(a, b, c, d, Block[4], 7, $F57C0FAF);
  FF(d, a, b, c, Block[5], 12, $4787C62A);
  FF(c, d, a, b, Block[6], 17, $A8304613);
  FF(b, c, d, a, Block[7], 22, $FD469501);
  FF(a, b, c, d, Block[8], 7, $698098D8);
  FF(d, a, b, c, Block[9], 12, $8B44F7AF);
  FF(c, d, a, b, Block[10], 17, $FFFF5BB1);
  FF(b, c, d, a, Block[11], 22, $895CD7BE);
  FF(a, b, c, d, Block[12], 7, $6B901122);
  FF(d, a, b, c, Block[13], 12, $FD987193);
  FF(c, d, a, b, Block[14], 17, $A679438E);
  FF(b, c, d, a, Block[15], 22, $49B40821);
  GG(a, b, c, d, Block[1], 5, $F61E2562);
  GG(d, a, b, c, Block[6], 9, $C040B340);
  GG(c, d, a, b, Block[11], 14, $265E5A51);
  GG(b, c, d, a, Block[0], 20, $E9B6C7AA);
  GG(a, b, c, d, Block[5], 5, $D62F105D);
  GG(d, a, b, c, Block[10], 9, $2441453);
  GG(c, d, a, b, Block[15], 14, $D8A1E681);
  GG(b, c, d, a, Block[4], 20, $E7D3FBC8);
  GG(a, b, c, d, Block[9], 5, $21E1CDE6);
  GG(d, a, b, c, Block[14], 9, $C33707D6);
  GG(c, d, a, b, Block[3], 14, $F4D50D87);
  GG(b, c, d, a, Block[8], 20, $455A14ED);
  GG(a, b, c, d, Block[13], 5, $A9E3E905);
  GG(d, a, b, c, Block[2], 9, $FCEFA3F8);
  GG(c, d, a, b, Block[7], 14, $676F02D9);
  GG(b, c, d, a, Block[12], 20, $8D2A4C8A);
  HH(a, b, c, d, Block[5], 4, $FFFA3942);
  HH(d, a, b, c, Block[8], 11, $8771F681);
  HH(c, d, a, b, Block[11], 16, $6D9D6122);
  HH(b, c, d, a, Block[14], 23, $FDE5380C);
  HH(a, b, c, d, Block[1], 4, $A4BEEA44);
  HH(d, a, b, c, Block[4], 11, $4BDECFA9);
  HH(c, d, a, b, Block[7], 16, $F6BB4B60);
  HH(b, c, d, a, Block[10], 23, $BEBFBC70);
  HH(a, b, c, d, Block[13], 4, $289B7EC6);
  HH(d, a, b, c, Block[0], 11, $EAA127FA);
  HH(c, d, a, b, Block[3], 16, $D4EF3085);
  HH(b, c, d, a, Block[6], 23, $4881D05);
  HH(a, b, c, d, Block[9], 4, $D9D4D039);
  HH(d, a, b, c, Block[12], 11, $E6DB99E5);
  HH(c, d, a, b, Block[15], 16, $1FA27CF8);
  HH(b, c, d, a, Block[2], 23, $C4AC5665);
  II(a, b, c, d, Block[0], 6, $F4292244);
  II(d, a, b, c, Block[7], 10, $432AFF97);
  II(c, d, a, b, Block[14], 15, $AB9423A7);
  II(b, c, d, a, Block[5], 21, $FC93A039);
  II(a, b, c, d, Block[12], 6, $655B59C3);
  II(d, a, b, c, Block[3], 10, $8F0CCC92);
  II(c, d, a, b, Block[10], 15, $FFEFF47D);
  II(b, c, d, a, Block[1], 21, $85845DD1);
  II(a, b, c, d, Block[8], 6, $6FA87E4F);
  II(d, a, b, c, Block[15], 10, $FE2CE6E0);
  II(c, d, a, b, Block[6], 15, $A3014314);
  II(b, c, d, a, Block[13], 21, $4E0811A1);
  II(a, b, c, d, Block[4], 6, $F7537E82);
  II(d, a, b, c, Block[11], 10, $BD3AF235);
  II(c, d, a, b, Block[2], 15, $2AD7D2BB);
  II(b, c, d, a, Block[9], 21, $EB86D391);
  inc(State[0], a);
  inc(State[1], b);
  inc(State[2], c);
  inc(State[3], d);
end;

procedure MD5Init(var Context: MD5Context);
begin
  with Context do begin
    State[0] := $67452301;
    State[1] := $EFCDAB89;
    State[2] := $98BADCFE;
    State[3] := $10325476;
    Count[0] := 0;
    Count[1] := 0;
    ZeroMemory(@Buffer, SizeOf(MD5Buffer));
  end;
end;

procedure MD5Update(var Context: MD5Context; Input: PAnsiChar; Length: longword);
var
  Index: longword;
  PartLen: longword;
  I: longword;
begin
  with Context do begin
    Index := (Count[0] shr 3) and $3F;
    inc(Count[0], Length shl 3);
    if Count[0] < (Length shl 3) then
      inc(Count[1]);
    inc(Count[1], Length shr 29);
  end;
  PartLen := 64 - Index;
  if Length >= PartLen then begin
    CopyMemory(@Context.Buffer[Index], Input, PartLen);
    Transform(@Context.Buffer, Context.State);
    I := PartLen;
    while I + 63 < Length do begin
      Transform(@Input[I], Context.State);
      inc(I, 64);
    end;
    Index := 0;
  end
  else
    I := 0;
  CopyMemory(@Context.Buffer[Index], @Input[I], Length - I);
end;

procedure MD5Result(var Context: MD5Context; var Digest: MD5Digest);
var
  Bits: MD5CBits;
  Index: longword;
  PadLen: longword;
begin
  Decode(@Context.Count, @Bits, 2);
  Index := (Context.Count[0] shr 3) and $3F;
  if Index < 56 then
    PadLen := 56 - Index
  else
    PadLen := 120 - Index;
  MD5Update(Context, @PADDING, PadLen);
  MD5Update(Context, @Bits, 8);
  Decode(@Context.State, @Digest, 4);
  ZeroMemory(@Context, SizeOf(MD5Context));
end;

function GetMD5Text(Input: string): string;
var
  Context: MD5Context;
  I: Byte;
  DigestResult: MD5Digest;
const
  Digits: array[0..15] of char = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f');
begin
  Result := '';
  MD5Init(Context);
  MD5Update(Context, PAnsiChar(AnsiString(Input)), Length(Input));
  MD5Result(Context, DigestResult);
  for I := 0 to 15 do
    Result := Result + Digits[(DigestResult[I] shr 4) and $0F] + Digits[DigestResult[I] and $0F];
end;

function GetMD5TextOf16(Input: string): string;
var
  Context: MD5Context;
  I: Byte;
  DigestResult: MD5Digest;
const
  Digits: array[0..15] of char = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f');
begin
  Result := '';
  MD5Init(Context);
  MD5Update(Context, PAnsiChar(AnsiString(Input)), Length(Input));
  MD5Result(Context, DigestResult);
  for I := 4 to 11 do
    Result := Result + Digits[(DigestResult[I] shr 4) and $0F] + Digits[DigestResult[I] and $0F];
end;

{
  CRC - Damian
}

procedure BuildCRCTable;
var
  i, j: Word;
  r: LongWord;
begin
  FillChar(CRCTable, SizeOf(CRCTable), 0);
  for i := 0 to 255 do begin
    r := i shl 1;
    for j := 8 downto 0 do
      if (r and 1) <> 0 then
        r := (r shr 1) xor CRCPOLY
      else
        r := r shr 1;
    CRCTable[i] := r;
  end;
end;

function RecountCRC(b: byte; CrcOld: Longint): Longint;
begin
  RecountCRC := CRCTable[byte(CrcOld xor Longint(b))] xor ((CrcOld shr 8) and $00FFFFFF)
end;

function GetCRC32(FileName: string): LongInt;
var
  Buffer: PAnsiChar;
  f: file of Byte;
  b: array[0..255] of Byte;
  CRC: LongWord;
  e, i: Integer;
begin
  BuildCRCTable;
  CRC := $FFFFFFFF;
  AssignFile(F, FileName);
  FileMode := 0;
  Reset(F);
  GetMem(Buffer, SizeOf(B));
  repeat
    FillChar(b, SizeOf(b), 0);
    BlockRead(F, b, SizeOf(b), e);
    for i := 0 to (e - 1) do
      CRC := RecountCRC(b[i], CRC);
  until (e < 255) or (IOresult <> 0);
  FreeMem(Buffer, SizeOf(B));
  CloseFile(F);
  CRC := not CRC;
  Result := CRC;
end;

function FileToMD5Text(const sFileName: string): string;
begin
  Result := MD5Print(GetMD5OfFile(sFileName, nil));
end;

function MD5Print(D: MD5Digest): string;
var
  I: byte;
const
  Digits: array[0..15] of char = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f');
begin
  Result := '';
  for I := 0 to 15 do
    Result := Result + Digits[(D[I] shr 4) and $0F] + Digits[D[I] and $0F];
end;

function GetMD5TextByBuffer(Buffer: PAnsiChar; BuffLen: Integer): string;
const
  BufSize = 16384;

var
  TotalSize, CurSize: Int64;
  Context: MD5Context;
  Size: DWORD;
  Digest: MD5Digest;
begin
  ZeroMemory(@Digest, Sizeof(MD5Digest));
  TotalSize := BuffLen;
  CurSize := 0;
  MD5Init(Context);
  while CurSize < TotalSize do begin
    if CurSize + BufSize <= TotalSize then Size := BufSize
    else Size := TotalSize - CurSize;
    MD5Update(Context, @Buffer[CurSize], Size);
    Inc(CurSize, Size);
  end;
  MD5Result(Context, Digest);
  Result := MD5Print(Digest);
end;

function GetMD5OfFile(const aFileName: string; aProgress: TProgressEvent; nOffset: Integer): MD5Digest;
const
  BufSize = 16384;

var
  f: TFileStream;
  Buf: array[0..BufSize - 1] of AnsiChar;
  TotalSize, CurSize: Int64;
  Context: MD5Context;
  Size: DWORD;
begin
  ZeroMemory(@Result, Sizeof(MD5Digest));
  if not FileExists(aFileName) then         //['{7DC20F45-B808-4DCF-98FC-C8A92B7A3ED8}']
    exit;

  f := TFileStream.Create(aFileName, fmOpenRead or fmShareDenyNone);
  try
    TotalSize := f.Size + nOffset;
    CurSize := 0;

    MD5Init(Context);
    if Assigned(aProgress) then
      aProgress(0);

    while CurSize < TotalSize do begin
      if CurSize + BufSize <= TotalSize then
        Size := BufSize
      else
        Size := TotalSize - CurSize;
      ZeroMemory(@Buf, Sizeof(Buf));
      f.Read(Buf, Size);
      Inc(CurSize, Size);

      MD5Update(Context, Buf, Size);

      if Assigned(aProgress) then
        aProgress(Round((CurSize / TotalSize) * 100));
    end;

    MD5Result(Context, Result);
  finally
    f.Free;

    if Assigned(aProgress) then
      aProgress(0);
  end;
end;

end.



