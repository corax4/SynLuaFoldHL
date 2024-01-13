{
MIT License

Copyright (c) 2023 Yuri Lychakov

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
}

unit SynLuaFoldHL;

{$mode ObjFPC}{$H+}
{$WARN 6058 off : Call to subroutine "$1" marked as inline is not inlined}
interface

uses
    Classes, SysUtils, Graphics, SynEditHighlighter, SynEditHighlighterFoldBase, SynEditStrConst, fgl;

type

    TAttriCond = record
        Attri: TSynHighlighterAttributes;
        Cond: ansistring;
    end;

    TKeyAttriMap = specialize TFPGMap<ansistring, TAttriCond>;

    { TSynLuaHL }

    TSynLuaHL = class(TSynCustomFoldHighlighter)
    private
        fCommentAttri: TSynHighlighterAttributes;
        fFunctionAttri: TSynHighlighterAttributes;
        fIdentifierAttri: TSynHighlighterAttributes;
        fKeyAttri: TSynHighlighterAttributes;
        fNumberAttri: TSynHighlighterAttributes;
        fSpaceAttri: TSynHighlighterAttributes;
        fStringAttri: TSynHighlighterAttributes;
        fSymbolAttri: TSynHighlighterAttributes;
        FUserFnAttri: TSynHighlighterAttributes;
        FUserVarAttri: TSynHighlighterAttributes;
        KeyAttriMap: TKeyAttriMap;
        function BlockSearchStart(TextBlock: boolean): boolean;
        procedure BlockSearchEnd;
        procedure SetUserFnAttri(AValue: TSynHighlighterAttributes);
        procedure SetUserVarAttri(AValue: TSynHighlighterAttributes);
        procedure TextSearchEnd(Quote: boolean);
        function CompKey(const key: ansistring): boolean;
        procedure InitKeyAttr;
        function PackACond(Attri: TSynHighlighterAttributes; Cond: ansistring): TAttriCond; inline;
    protected
        FTokenPos, FTokenEnd: integer;
        FLine: ansistring;
        FCurRange: integer; // '1 "2 --[1000..1999  [[2000..2999
        AttribArr: array [0..9] of TSynHighlighterAttributes;
    public
        procedure SetLine(const NewValue: string; LineNumber: integer); override;
        procedure Next; override;
        function GetEol: boolean; override;
        procedure GetTokenEx(out TokenStart: PChar; out TokenLength: integer); override;
        function GetTokenAttribute: TSynHighlighterAttributes; override;
    public
        function GetToken: string; override;
        function GetTokenPos: integer; override;
        function GetTokenKind: integer; override;
        function GetDefaultAttribute(Index: integer): TSynHighlighterAttributes; override;
        constructor Create(AOwner: TComponent); override;
        procedure SetRange(Value: Pointer); override;
        procedure ResetRange; override;
        function GetRange: Pointer; override;
        procedure AddUserFunction(s: ansistring; Condition: ansistring = '');
        procedure AddUserVar(s: ansistring; Condition: ansistring = '');
        procedure AddKeyword(s: ansistring; AttribNum: byte; Condition: ansistring = '');
        procedure DelKeyword(s: ansistring);
    published
        property CommentAttri: TSynHighlighterAttributes read fCommentAttri write fCommentAttri;
        property FunctionAttri: TSynHighlighterAttributes read fFunctionAttri write fFunctionAttri;
        property IdentifierAttri: TSynHighlighterAttributes read fIdentifierAttri write fIdentifierAttri;
        property KeyAttri: TSynHighlighterAttributes read fKeyAttri write fKeyAttri;
        property NumberAttri: TSynHighlighterAttributes read fNumberAttri write fNumberAttri;
        property SpaceAttri: TSynHighlighterAttributes read fSpaceAttri write fSpaceAttri;
        property StringAttri: TSynHighlighterAttributes read fStringAttri write fStringAttri;
        property SymbolAttri: TSynHighlighterAttributes read fSymbolAttri write fSymbolAttri;
        property UserFnAttri: TSynHighlighterAttributes read FUserFnAttri write SetUserFnAttri;
        property UserVarAttri: TSynHighlighterAttributes read FUserVarAttri write SetUserVarAttri;
    end;

implementation

var
    // -1 NULL, 0 spaces, 1 symbols, 2 _letters, 3 num
    SymTypes: array [#0..#255] of shortint;

    { TSynLuaHL }

constructor TSynLuaHL.Create(AOwner: TComponent);
var
    i: byte;
begin
    inherited Create(AOwner);

    fCommentAttri := TSynHighlighterAttributes.Create({$IFDEF FPC}@{$ENDIF}SYNS_AttrComment, SYNS_XML_AttrComment);
    AddAttribute(fCommentAttri);
    fCommentAttri.Foreground := clSilver;

    fFunctionAttri := TSynHighlighterAttributes.Create({$IFDEF FPC}@{$ENDIF}SYNS_AttrFunction, SYNS_XML_AttrFunction);
    AddAttribute(fFunctionAttri);
    fFunctionAttri.Foreground := $2080C0;

    fIdentifierAttri := TSynHighlighterAttributes.Create({$IFDEF FPC}@{$ENDIF}SYNS_AttrIdentifier, SYNS_XML_AttrIdentifier);
    AddAttribute(fIdentifierAttri);

    fKeyAttri := TSynHighlighterAttributes.Create({$IFDEF FPC}@{$ENDIF}SYNS_AttrReservedWord, SYNS_XML_AttrReservedWord);
    AddAttribute(fKeyAttri);
    fKeyAttri.Style := [fsBold];

    fNumberAttri := TSynHighlighterAttributes.Create({$IFDEF FPC}@{$ENDIF}SYNS_AttrNumber, SYNS_XML_AttrNumber);
    AddAttribute(fNumberAttri);
    fNumberAttri.Foreground := clFuchsia;

    fSpaceAttri := TSynHighlighterAttributes.Create({$IFDEF FPC}@{$ENDIF}SYNS_AttrSpace, SYNS_XML_AttrSpace);
    AddAttribute(fSpaceAttri);

    fStringAttri := TSynHighlighterAttributes.Create({$IFDEF FPC}@{$ENDIF}SYNS_AttrString, SYNS_XML_AttrString);
    AddAttribute(fStringAttri);
    fStringAttri.Foreground := clOlive;

    fSymbolAttri := TSynHighlighterAttributes.Create({$IFDEF FPC}@{$ENDIF}SYNS_AttrSymbol, SYNS_XML_AttrSymbol);
    AddAttribute(fSymbolAttri);
    fSymbolAttri.Foreground := clBlue;

    FUserFnAttri := TSynHighlighterAttributes.Create({$IFDEF FPC}@{$ENDIF}SYNS_AttrUserFunction, SYNS_XML_AttrUserFunction);
    AddAttribute(FUserFnAttri);

    FUserVarAttri := TSynHighlighterAttributes.Create({$IFDEF FPC}@{$ENDIF}SYNS_AttrUser, SYNS_XML_AttrUser);
    AddAttribute(FUserVarAttri);

    SetAttributesOnChange({$IFDEF FPC}@{$ENDIF}DefHighlightChange);

    AttribArr[SYN_ATTR_COMMENT] := fCommentAttri;
    AttribArr[SYN_ATTR_IDENTIFIER] := IdentifierAttri;
    AttribArr[SYN_ATTR_KEYWORD] := KeyAttri;
    AttribArr[SYN_ATTR_STRING] := StringAttri;
    AttribArr[SYN_ATTR_WHITESPACE] := SpaceAttri;
    AttribArr[SYN_ATTR_SYMBOL] := SymbolAttri;
    AttribArr[SYN_ATTR_NUMBER] := NumberAttri;
    AttribArr[SYN_ATTR_DIRECTIVE] := FunctionAttri;
    AttribArr[SYN_ATTR_ASM] := FUserFnAttri;
    AttribArr[SYN_ATTR_VARIABLE] := FUserVarAttri;

    KeyAttriMap := TKeyAttriMap.Create;
    KeyAttriMap.Sorted := True;
    InitKeyAttr;

    for i := 1 to 32 do SymTypes[char(i)] := 0; // spaces
    for i := 33 to 128 do SymTypes[char(i)] := 1; // sybmols
    for i := 48 to 57 do SymTypes[char(i)] := 3; // numbers
    for i := 65 to 90 do SymTypes[char(i)] := 2; // A..Z
    for i := 97 to 122 do SymTypes[char(i)] := 2; // a..z
    for i := 128 to 255 do SymTypes[char(i)] := 2; // non-ASCII
    SymTypes['_'] := 2; // _
    SymTypes[#0] := -1; // NULL
end;

procedure TSynLuaHL.AddKeyword(s: ansistring; AttribNum: byte; Condition: ansistring);
var
    ACond: TAttriCond;
begin
    ACond.Attri := AttribArr[AttribNum];
    ACond.Cond := Condition;
    KeyAttriMap[s] := ACond;
end;

procedure TSynLuaHL.AddUserFunction(s: ansistring; Condition: ansistring);
var
    ACond: TAttriCond;
begin
    ACond.Attri := FUserFnAttri;
    ACond.Cond := Condition;
    KeyAttriMap[s] := ACond;
end;

procedure TSynLuaHL.AddUserVar(s: ansistring; Condition: ansistring);
var
    ACond: TAttriCond;
begin
    ACond.Attri := FUserVarAttri;
    ACond.Cond := Condition;
    KeyAttriMap[s] := ACond;
end;

procedure TSynLuaHL.BlockSearchEnd;
var
    n, m: integer;
begin
    if FCurRange < 1000 then exit;
    n := FCurRange - 999;
    if FCurRange >= 2000 then
        n := n - 1000;
    m := 0;
    // search for block ending of EOL
    while (FLine[FTokenEnd] <> #0) do
    begin
        if (FLine[FTokenEnd] = '=') and (m > 0) then Inc(m);
        if (FLine[FTokenEnd] = ']') then
            if m = 0 then
                m := 1
            else // probably end of block
            begin
                if m <> n then
                    m := 1
                else // realy end!
                begin
                    Inc(FTokenEnd);
                    EndCodeFoldBlock();
                    if FCurRange >= 2000 then
                        FCurRange := -2
                    else
                        FCurRange := -1;
                    exit;
                end;
            end;
        if (FLine[FTokenEnd] <> '=') and (FLine[FTokenEnd] <> ']') then m := 0;
        Inc(FTokenEnd);
    end;
end;

function TSynLuaHL.BlockSearchStart(TextBlock: boolean): boolean;
var
    n: integer;
begin
    Result := False;
    n := 1; // probably start block
    if FLine[FTokenEnd] = #0 then exit;
    while (FLine[FTokenEnd] = '=') do
    begin
        Inc(n);
        Inc(FTokenEnd);
    end;
    if FLine[FTokenEnd] = '[' then  // realy block
    begin
        Inc(FTokenEnd);
        FCurRange := 999 + n;
        if TextBlock then FCurRange := FCurRange + 1000;
        Result := True;
        StartCodeFoldBlock(nil);
        BlockSearchEnd; // search for block ending of EOL
    end;
end;

function TSynLuaHL.CompKey(const key: ansistring): boolean;
var
    len, i, j: integer;
begin
    len := Length(key);
    if (FTokenEnd - FTokenPos) <> len then Exit(False);
    Result := True;
    j := FTokenPos;
    for i := 1 to len do
    begin
        if FLine[j] <> key[i] then Exit(False);
        Inc(j);
    end;
end;

procedure TSynLuaHL.DelKeyword(s: ansistring);
begin
    KeyAttriMap.Remove(s);
end;

function TSynLuaHL.GetDefaultAttribute(Index: integer): TSynHighlighterAttributes;
begin
    if (Index < Low(AttribArr)) or (Index > High(AttribArr)) then
        Result := nil
    else
        Result := AttribArr[Index];
end;

function TSynLuaHL.GetEol: boolean;
begin
    Result := FTokenPos > Length(FLine);
end;

function TSynLuaHL.GetRange: Pointer;
begin
    CodeFoldRange.RangeType := Pointer(PtrInt(FCurRange));
    Result := inherited GetRange;
end;

function TSynLuaHL.GetToken: string;
begin
    Result := Copy(FLine, FTokenPos, FTokenEnd - FTokenPos);
end;

function TSynLuaHL.GetTokenAttribute: TSynHighlighterAttributes;
var
    ACond: TAttriCond;
    len: integer;
begin
    Result := fIdentifierAttri;
    if FCurRange >= 2000 then
        Result := fStringAttri
    else
    if FCurRange >= 1000 then
        Result := fCommentAttri
    else
    if FCurRange > 0 then
        Result := fStringAttri
    else
    if FCurRange = -1 then
        Result := fCommentAttri
    else
    if FCurRange = -2 then
        Result := fStringAttri;
    if FCurRange < 0 then FCurRange := 0;
    if Result <> fIdentifierAttri then exit;



    case SymTypes[FLine[FTokenPos]] of
        0: Result := fSpaceAttri;
        1: begin
            Result := fSymbolAttri;
            case FLine[FTokenPos] of
                '-': if (FLine[FTokenPos + 1] = '-') then
                        Result := fCommentAttri;
                '''': Result := fStringAttri;
                '"': Result := fStringAttri;
                '[': if (FLine[FTokenPos + 1] = '[') then
                        Result := fStringAttri;
            end;
        end;
        2: begin
            Result := fIdentifierAttri;
            if KeyAttriMap.TryGetData(copy(FLine, FTokenPos, FTokenEnd - FTokenPos), ACond) then
            begin
                if ACond.Cond = '' then
                    Result := ACond.Attri
                else if ACond.Cond = ' ' then  // do not highlight members of tables
                begin
                    if FTokenPos <= 1 then  // start of line
                        Result := ACond.Attri
                    else
                    if FLine[FTokenPos - 1] = '.' then // can be ..
                    begin
                        if FTokenPos > 2 then
                            if FLine[FTokenPos - 2] = '.' then
                                Result := ACond.Attri;
                    end
                    else
                        if FLine[FTokenPos - 1] <> ':' then
                            Result := ACond.Attri;
                end
                else
                begin // some condition
                    len := length(ACond.Cond);
                    if len < FTokenPos then
                        if Copy(FLine, FTokenPos - len, len) = ACond.Cond then
                            if FTokenPos - len <= 1 then  // start of line
                                Result := ACond.Attri
                            else
                            if SymTypes[FLine[FTokenPos - len - 1]] <> 2 then // full ID
                                if FLine[FTokenPos - len - 1] = '.' then // can be ..
                                begin
                                    if FTokenPos - len > 2 then
                                        if FLine[FTokenPos - len - 2] = '.' then
                                            Result := ACond.Attri;
                                end
                                else
                                    Result := ACond.Attri;
                end;
            end;
        end;
        3: Result := fNumberAttri;
    end;
end;

procedure TSynLuaHL.GetTokenEx(out TokenStart: PChar; out TokenLength: integer);
begin
    TokenStart := @FLine[FTokenPos];
    TokenLength := FTokenEnd - FTokenPos;
end;

function TSynLuaHL.GetTokenKind: integer;
var
    a: TSynHighlighterAttributes;
begin
    a := GetTokenAttribute;
    Result := 0;
    if a = fCommentAttri then Result := SYN_ATTR_COMMENT;
    if a = fFunctionAttri then Result := SYN_ATTR_DIRECTIVE;
    if a = fIdentifierAttri then Result := SYN_ATTR_IDENTIFIER;
    if a = fKeyAttri then Result := SYN_ATTR_KEYWORD;
    if a = fNumberAttri then Result := SYN_ATTR_NUMBER;
    if a = fSpaceAttri then Result := SYN_ATTR_WHITESPACE;
    if a = fStringAttri then Result := SYN_ATTR_STRING;
    if a = fSymbolAttri then Result := SYN_ATTR_SYMBOL;
    if a = FUserFnAttri then Result := SYN_ATTR_ASM;
    if a = FUserVarAttri then Result := SYN_ATTR_VARIABLE;
end;

function TSynLuaHL.GetTokenPos: integer;
begin
    Result := FTokenPos - 1;
end;

procedure TSynLuaHL.InitKeyAttr;
begin
    KeyAttriMap['and']      := PackACond(fKeyAttri, '');
    KeyAttriMap['assert']   := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['break']    := PackACond(fKeyAttri, '');
    KeyAttriMap['collectgarbage']    := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['do']       := PackACond(fKeyAttri, '');
    KeyAttriMap['dofile']   := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['else']     := PackACond(fKeyAttri, '');
    KeyAttriMap['elseif']   := PackACond(fKeyAttri, '');
    KeyAttriMap['end']      := PackACond(fKeyAttri, '');
    KeyAttriMap['error']    := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['false']    := PackACond(fKeyAttri, '');
    KeyAttriMap['for']      := PackACond(fKeyAttri, '');
    KeyAttriMap['function'] := PackACond(fKeyAttri, '');
    KeyAttriMap['goto']     := PackACond(fKeyAttri, '');
    KeyAttriMap['getfenv']  := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['getmetatable'] := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['if']       := PackACond(fKeyAttri, '');
    KeyAttriMap['in']       := PackACond(fKeyAttri, '');
    KeyAttriMap['ipairs']   := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['local']    := PackACond(fKeyAttri, '');
    KeyAttriMap['load']     := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['loadfile'] := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['loadstring'] := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['module']   := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['nil']      := PackACond(fKeyAttri, '');
    KeyAttriMap['not']      := PackACond(fKeyAttri, '');
    KeyAttriMap['next']     := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['or']       := PackACond(fKeyAttri, '');
    KeyAttriMap['pairs']    := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['pcall']    := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['print']    := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['repeat']   := PackACond(fKeyAttri, '');
    KeyAttriMap['return']   := PackACond(fKeyAttri, '');
    KeyAttriMap['rawequal'] := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['rawget']   := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['rawset']   := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['require']  := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['select']   := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['setfenv']  := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['setmetatable'] := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['then']     := PackACond(fKeyAttri, '');
    KeyAttriMap['true']     := PackACond(fKeyAttri, '');
    KeyAttriMap['tonumber'] := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['tostring'] := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['type']     := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['until']    := PackACond(fKeyAttri, '');
    KeyAttriMap['unpack']   := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['while']    := PackACond(fKeyAttri, '');
    KeyAttriMap['xpcall']   := PackACond(fFunctionAttri, ' ');

    // ***** Libs *****

    KeyAttriMap['coroutine'] := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['create']    := PackACond(fFunctionAttri, 'coroutine.');
    KeyAttriMap['resume']    := PackACond(fFunctionAttri, 'coroutine.');
    KeyAttriMap['running']   := PackACond(fFunctionAttri, 'coroutine.');
    KeyAttriMap['status']    := PackACond(fFunctionAttri, 'coroutine.');
    KeyAttriMap['wrap']      := PackACond(fFunctionAttri, 'coroutine.');
    KeyAttriMap['yield']     := PackACond(fFunctionAttri, 'coroutine.');

    KeyAttriMap['debug']     := PackACond(fFunctionAttri, ' ');
    //KeyAttriMap['debug']   := PackACond(fFunctionAttri, 'debug.');
    //KeyAttriMap['getfenv'] := PackACond(fFunctionAttri, 'debug.');
    KeyAttriMap['gethook']   := PackACond(fFunctionAttri, 'debug.');
    KeyAttriMap['getinfo']   := PackACond(fFunctionAttri, 'debug.');
    KeyAttriMap['getlocal']  := PackACond(fFunctionAttri, 'debug.');
    //KeyAttriMap['getmetatable'] := PackACond(fFunctionAttri, 'debug.');
    KeyAttriMap['getregistry'] := PackACond(fFunctionAttri, 'debug.');
    KeyAttriMap['getupvalue']  := PackACond(fFunctionAttri, 'debug.');
    //KeyAttriMap['setfenv']   := PackACond(fFunctionAttri, 'debug.');
    KeyAttriMap['sethook']     := PackACond(fFunctionAttri, 'debug.');
    KeyAttriMap['setlocal']    := PackACond(fFunctionAttri, 'debug.');
    //KeyAttriMap['setmetatable'] := PackACond(fFunctionAttri, 'debug.');
    KeyAttriMap['setupvalue']  := PackACond(fFunctionAttri, 'debug.');
    KeyAttriMap['traceback']   := PackACond(fFunctionAttri, 'debug.');

    KeyAttriMap['io']      := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['close']   := PackACond(fFunctionAttri, 'io.');
    KeyAttriMap['flush']   := PackACond(fFunctionAttri, 'io.');
    KeyAttriMap['input']   := PackACond(fFunctionAttri, 'io.');
    KeyAttriMap['lines']   := PackACond(fFunctionAttri, 'io.');
    KeyAttriMap['open']    := PackACond(fFunctionAttri, 'io.');
    KeyAttriMap['output']  := PackACond(fFunctionAttri, 'io.');
    KeyAttriMap['popen']   := PackACond(fFunctionAttri, 'io.');
    KeyAttriMap['read']    := PackACond(fFunctionAttri, 'io.');
    KeyAttriMap['stderr']  := PackACond(fFunctionAttri, 'io.');
    KeyAttriMap['stdin']   := PackACond(fFunctionAttri, 'io.');
    KeyAttriMap['stdout']  := PackACond(fFunctionAttri, 'io.');
    KeyAttriMap['tmpfile'] := PackACond(fFunctionAttri, 'io.');
    //KeyAttriMap['type']  := PackACond(fFunctionAttri, 'io.');
    KeyAttriMap['write']   := PackACond(fFunctionAttri, 'io.');

    KeyAttriMap['math']   := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['abs']    := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['acos']   := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['asin']   := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['atan']   := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['atan2']  := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['ceil']   := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['cos']    := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['cosh']   := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['deg']    := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['exp']    := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['floor']  := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['fmod']   := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['frexp']  := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['huge']   := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['ldexp']  := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['log']    := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['log10']  := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['max']    := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['min']    := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['modf']   := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['pi']     := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['pow']    := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['rad']    := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['random'] := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['randomseed'] := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['sin']    := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['sinh']   := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['sqrt']   := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['tan']    := PackACond(fFunctionAttri, 'math.');
    KeyAttriMap['tanh']   := PackACond(fFunctionAttri, 'math.');

    KeyAttriMap['os']        := PackACond(fFunctionAttri, 'os.');
    KeyAttriMap['clock']     := PackACond(fFunctionAttri, 'os.');
    KeyAttriMap['date']      := PackACond(fFunctionAttri, 'os.');
    KeyAttriMap['difftime']  := PackACond(fFunctionAttri, 'os.');
    KeyAttriMap['execute']   := PackACond(fFunctionAttri, 'os.');
    KeyAttriMap['exit']      := PackACond(fFunctionAttri, 'os.');
    KeyAttriMap['getenv']    := PackACond(fFunctionAttri, 'os.');
    //KeyAttriMap['remove']    := PackACond(fFunctionAttri, 'os.');
    KeyAttriMap['rename']    := PackACond(fFunctionAttri, 'os.');
    KeyAttriMap['setlocale'] := PackACond(fFunctionAttri, 'os.');
    KeyAttriMap['time']      := PackACond(fFunctionAttri, 'os.');
    KeyAttriMap['tmpname']   := PackACond(fFunctionAttri, 'os.');

    KeyAttriMap['package']   := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['cpath']     := PackACond(fFunctionAttri, 'package.');
    KeyAttriMap['loaded']    := PackACond(fFunctionAttri, 'package.');
    KeyAttriMap['loaders']   := PackACond(fFunctionAttri, 'package.');
    KeyAttriMap['loadlib']   := PackACond(fFunctionAttri, 'package.');
    KeyAttriMap['path']      := PackACond(fFunctionAttri, 'package.');
    KeyAttriMap['preload']   := PackACond(fFunctionAttri, 'package.');
    KeyAttriMap['seeall']    := PackACond(fFunctionAttri, 'package.');

    KeyAttriMap['string']   := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['byte']     := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['char']     := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['dump']     := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['find']     := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['format']   := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['gmatch']   := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['gsub']     := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['len']      := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['lower']    := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['match']    := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['rep']      := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['reverse']  := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['sub']      := PackACond(fFunctionAttri, 'string.');
    KeyAttriMap['upper']    := PackACond(fFunctionAttri, 'string.');

    KeyAttriMap['table']    := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['concat']   := PackACond(fFunctionAttri, 'table.');
    KeyAttriMap['insert']   := PackACond(fFunctionAttri, 'table.');
    KeyAttriMap['maxn']     := PackACond(fFunctionAttri, 'table.');
    KeyAttriMap['remove'] := PackACond(fFunctionAttri, 'table.');
    KeyAttriMap['sort']     := PackACond(fFunctionAttri, 'table.');

    // ***** LuaJIT *****
    KeyAttriMap['ffi']      := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['cdef']     := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['C']        := PackACond(fFunctionAttri, 'ffi.');
    //KeyAttriMap['load']   := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['new']      := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['typeof']   := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['cast']     := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['metatype'] := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['gc']       := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['free']     := PackACond(fFunctionAttri, 'ffi.C.');
    KeyAttriMap['sizeof']   := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['alignof']  := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['offsetof'] := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['istype']   := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['errno']    := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['copy']     := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['fill']     := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['abi']      := PackACond(fFunctionAttri, 'ffi.');
    KeyAttriMap['arch']     := PackACond(fFunctionAttri, 'ffi.');

    KeyAttriMap['bit']     := PackACond(fFunctionAttri, ' ');
    KeyAttriMap['tobit']   := PackACond(fFunctionAttri, 'bit.');
    KeyAttriMap['tohex']   := PackACond(fFunctionAttri, 'bit.');
    KeyAttriMap['bnot']    := PackACond(fFunctionAttri, 'bit.');
    KeyAttriMap['band']    := PackACond(fFunctionAttri, 'bit.');
    KeyAttriMap['bor']     := PackACond(fFunctionAttri, 'bit.');
    KeyAttriMap['bxor']    := PackACond(fFunctionAttri, 'bit.');
    KeyAttriMap['lshift']  := PackACond(fFunctionAttri, 'bit.');
    KeyAttriMap['rshift']  := PackACond(fFunctionAttri, 'bit.');
    KeyAttriMap['arshift'] := PackACond(fFunctionAttri, 'bit.');
    KeyAttriMap['rol']     := PackACond(fFunctionAttri, 'bit.');
    KeyAttriMap['ror']     := PackACond(fFunctionAttri, 'bit.');
    KeyAttriMap['bswap']   := PackACond(fFunctionAttri, 'bit.');

end;

function TSynLuaHL.PackACond(Attri: TSynHighlighterAttributes; Cond: ansistring): TAttriCond;
begin
    Result.Attri := Attri;
    Result.Cond := Cond;
end;

procedure TSynLuaHL.Next;
begin
    FTokenPos := FTokenEnd; // start of the next Token

    if FTokenPos > Length(FLine) then exit; // EOL

    if SymTypes[FLine[FTokenEnd]] = -1 then  // NULL
    begin
        Inc(FTokenEnd);
        exit;
    end;

    if FCurRange >= 1000 then
    begin
        BlockSearchEnd;
        exit;
    end;
    if FCurRange > 0 then
    begin
        TextSearchEnd(FCurRange = 1);
        if FCurRange = 0 then
            FCurRange := -2;
        exit;
    end;
    if FCurRange < 0 then FCurRange := 0;


    if SymTypes[FLine[FTokenEnd]] = 0 then  // space
    begin
        while (SymTypes[FLine[FTokenEnd]] = 0) do Inc(FTokenEnd);
        exit;
    end;

    if (SymTypes[FLine[FTokenEnd]] = 3) then  // num
    begin
        while (FLine[FTokenEnd] in ['0'..'9', 'x', 'X', 'e', 'E', 'p', 'P', '.']) do
        begin
            if (FLine[FTokenEnd] = '.') and (FLine[FTokenEnd + 1] = '.') then Break;
            Inc(FTokenEnd);
        end;
        exit;
    end;

    if SymTypes[FLine[FTokenEnd]] = 1 then  // symbol
    begin
        Inc(FTokenEnd);

        case FLine[FTokenEnd - 1] of
            '-': if (FLine[FTokenEnd] = '-') then  // it's comment
                begin
                    Inc(FTokenEnd);
                    if FLine[FTokenEnd] = #0 then exit;
                    if FLine[FTokenEnd] = '[' then
                    begin
                        Inc(FTokenEnd);
                        if not BlockSearchStart(False) then // not a block, just line
                            while (FLine[FTokenEnd] <> #0) do Inc(FTokenEnd);
                        if FCurRange < 0 then FCurRange := 0;
                    end
                    else
                        while (FLine[FTokenEnd] <> #0) do Inc(FTokenEnd);
                end;

            '[': BlockSearchStart(True);
            '''': TextSearchEnd(True);
            '"': TextSearchEnd(False);
            '{': StartCodeFoldBlock(nil);
            '}': EndCodeFoldBlock;
        end;
        exit;
    end;

    if SymTypes[FLine[FTokenEnd]] = 2 then  // ident
    begin
        while (SymTypes[FLine[FTokenEnd]] >= 2) do Inc(FTokenEnd);
        case FLine[FTokenPos] of
            'd': if CompKey('do') then StartCodeFoldBlock(nil);
            'e': begin
                if CompKey('else') then
                begin
                    EndCodeFoldBlock;
                    StartCodeFoldBlock(nil);
                end;
                if CompKey('elseif') then
                begin
                    EndCodeFoldBlock;
                    StartCodeFoldBlock(nil);
                end;
                if CompKey('end') then EndCodeFoldBlock;
            end;
            'f': if CompKey('function') then StartCodeFoldBlock(nil);
            'i': if CompKey('if') then StartCodeFoldBlock(nil);
            'r': if CompKey('repeat') then StartCodeFoldBlock(nil);
            'u': if CompKey('until') then EndCodeFoldBlock;
        end;
        exit;
    end;
end;

procedure TSynLuaHL.ResetRange;
begin
    inherited ResetRange;
    FCurRange := 0;
end;

procedure TSynLuaHL.SetLine(const NewValue: string; LineNumber: integer);
begin
    inherited;
    FLine := NewValue;
    // Next will start at "FTokenEnd", so set this to 1
    FTokenEnd := 1;
    Next;
end;

procedure TSynLuaHL.SetRange(Value: Pointer);
begin
    inherited SetRange(Value);
    FCurRange := PtrInt(CodeFoldRange.RangeType);
end;

procedure TSynLuaHL.SetUserFnAttri(AValue: TSynHighlighterAttributes);
begin
    if FUserFnAttri = AValue then Exit;
    FUserFnAttri := AValue;
end;

procedure TSynLuaHL.SetUserVarAttri(AValue: TSynHighlighterAttributes);
begin
    if FUserVarAttri = AValue then Exit;
    FUserVarAttri := AValue;
end;

procedure TSynLuaHL.TextSearchEnd(Quote: boolean);
var
    ch: char;
begin
    FCurRange := 0;
    if FLine[FTokenEnd] = #0 then exit;
    if Quote then ch := ''''
    else
        ch := '"';
    if FLine[FTokenEnd] = ch then
    begin
        Inc(FTokenEnd);
        exit;
    end;
    repeat
        if (FCurRange <> 0) and (SymTypes[FLine[FTokenEnd]] > 0) then
            FCurRange := 0;
        if FLine[FTokenEnd] = '\' then
        begin
            if FLine[FTokenEnd + 1] in ['z', 'Z'] then
            begin
                if Quote then FCurRange := 1
                else
                    FCurRange := 2;
                Inc(FTokenEnd);
            end
            else
            if FLine[FTokenEnd + 1] in ['\', ch] then
                Inc(FTokenEnd);
        end;
        Inc(FTokenEnd);
    until FLine[FTokenEnd] in [#0, ch];
    if FLine[FTokenEnd] = ch then
    begin
        FCurRange := 0;
        Inc(FTokenEnd);
    end;
end;

end.
