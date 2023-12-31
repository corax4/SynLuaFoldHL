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

interface

uses
    Classes, SysUtils, Graphics, SynEditHighlighter, SynEditHighlighterFoldBase, SynEditStrConst;

type

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
        function BlockSearchStart(TextBlock: Boolean): Boolean;
        procedure BlockSearchEnd;
        procedure TextSearchEnd(Quote: Boolean);
        function CompKey(const key: ansistring): Boolean;
    protected
        FTokenPos, FTokenEnd: integer;
        FLine: ansistring;
        FCurRange: Integer; // '1 "2 --[1000..1999  [[2000..2999
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
    published
        property CommentAttri: TSynHighlighterAttributes read fCommentAttri write fCommentAttri;
        property FunctionAttri: TSynHighlighterAttributes read fFunctionAttri write fFunctionAttri;
        property IdentifierAttri: TSynHighlighterAttributes read fIdentifierAttri write fIdentifierAttri;
        property KeyAttri: TSynHighlighterAttributes read fKeyAttri write fKeyAttri;
        property NumberAttri: TSynHighlighterAttributes read fNumberAttri write fNumberAttri;
        property SpaceAttri: TSynHighlighterAttributes read fSpaceAttri write fSpaceAttri;
        property StringAttri: TSynHighlighterAttributes read fStringAttri write fStringAttri;
        property SymbolAttri: TSynHighlighterAttributes read fSymbolAttri write fSymbolAttri;
    end;

implementation

var
    // -1 NULL, 0 spaces, 1 symbols, 2 _letters, 3 num
    SymTypes: array [#0..#255] of ShortInt;

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
    fFunctionAttri.Foreground := clTeal;

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

    SetAttributesOnChange({$IFDEF FPC}@{$ENDIF}DefHighlightChange);

    for i := 1   to 32  do SymTypes[Char(i)] := 0; // spaces
    for i := 33  to 128 do SymTypes[Char(i)] := 1; // sybmols
    for i := 48  to 57  do SymTypes[Char(i)] := 3; // numbers
    for i := 65  to 90  do SymTypes[Char(i)] := 2; // A..Z
    for i := 97  to 122 do SymTypes[Char(i)] := 2; // a..z
    for i := 128 to 255 do SymTypes[Char(i)] := 2; // non-ASCII
    SymTypes['_'] := 2; // _
    SymTypes[#0] := -1; // NULL
end;

procedure TSynLuaHL.BlockSearchEnd;
var
    n, m: Integer;
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

function TSynLuaHL.BlockSearchStart(TextBlock: Boolean): Boolean;
var
    n: Integer;
begin
    Result := false;
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
        Result := true;
        StartCodeFoldBlock(nil);
        BlockSearchEnd; // search for block ending of EOL
    end;
end;

function TSynLuaHL.CompKey(const key: ansistring): Boolean;
var
    len , i, j: integer;
begin
    len := Length(key);
    if (FTokenEnd - FTokenPos) <> len then Exit(false);
    Result := true;
    j := FTokenPos;
    for i := 1 to len do
    begin
        if FLine[j] <> key[i] then Exit(False);
        Inc(j);
    end;
end;

function TSynLuaHL.GetDefaultAttribute(Index: integer): TSynHighlighterAttributes;
begin
    case Index of
        SYN_ATTR_COMMENT: Result := fCommentAttri;
        SYN_ATTR_IDENTIFIER: Result := IdentifierAttri;
        SYN_ATTR_WHITESPACE: Result := SpaceAttri;
        SYN_ATTR_KEYWORD: Result := KeyAttri;
        SYN_ATTR_STRING: Result := StringAttri;
        SYN_ATTR_SYMBOL: Result := SymbolAttri;
        SYN_ATTR_NUMBER: Result := NumberAttri;
        SYN_ATTR_DIRECTIVE: Result := FunctionAttri;
        else
            Result := nil;
    end;
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
        0:  Result := fSpaceAttri;
        1:  begin
                Result := fSymbolAttri;
                case FLine[FTokenPos] of
                    '-':    if (FLine[FTokenPos + 1] = '-') then
                                Result := fCommentAttri;
                    '''':   Result := fStringAttri;
                    '"':    Result := fStringAttri;
                    '[':    if (FLine[FTokenPos + 1] = '[') then
                                Result := fStringAttri;
                end;
            end;
        2:  begin
                Result := fIdentifierAttri;
                case FLine[FTokenPos] of
                    'a':    begin
                                if CompKey('and') then      Result := fKeyAttri;
                                if CompKey('assert') then   Result := fFunctionAttri;
                            end;
                    'b':    if CompKey('break') then    Result := fKeyAttri;
                    'c':    if CompKey('collectgarbage') then    Result := fFunctionAttri;
                    'd':    begin
                                if CompKey('do') then       Result := fKeyAttri;
                                if CompKey('dofile') then    Result := fFunctionAttri;
                            end;
                    'e':    begin
                                if CompKey('else') then     Result := fKeyAttri;
                                if CompKey('elseif') then   Result := fKeyAttri;
                                if CompKey('end') then      Result := fKeyAttri;
                                if CompKey('error') then      Result := fFunctionAttri;
                            end;
                    'f':    begin
                                if CompKey('false') then    Result := fKeyAttri;
                                if CompKey('for') then      Result := fKeyAttri;
                                if CompKey('function') then Result := fKeyAttri;
                            end;
                    'g':    begin
                                if CompKey('goto') then     Result := fKeyAttri;
                                if CompKey('getfenv') then      Result := fFunctionAttri;
                                if CompKey('getmetatable') then Result := fFunctionAttri;
                            end;
                    'i':    begin
                                if CompKey('if') then       Result := fKeyAttri;
                                if CompKey('in') then       Result := fKeyAttri;
                                if CompKey('ipairs') then   Result := fFunctionAttri;
                            end;
                    'l':    begin
                                if CompKey('local') then    Result := fKeyAttri;
                                if CompKey('load') then     Result := fFunctionAttri;
                                if CompKey('loadfile') then     Result := fFunctionAttri;
                                if CompKey('loadstring') then   Result := fFunctionAttri;
                            end;
                    'm':    if CompKey('module') then   Result := fFunctionAttri;
                    'n':    begin
                                if CompKey('nil') then  Result := fKeyAttri;
                                if CompKey('not') then  Result := fKeyAttri;
                                if CompKey('next') then Result := fFunctionAttri;
                            end;
                    'o':    if CompKey('or') then       Result := fKeyAttri;
                    'p':    begin
                                if CompKey('pairs') then Result := fFunctionAttri;
                                if CompKey('pcall') then Result := fFunctionAttri;
                                if CompKey('print') then Result := fFunctionAttri;
                            end;
                    'r':    begin
                                if CompKey('repeat') then   Result := fKeyAttri;
                                if CompKey('return') then   Result := fKeyAttri;
                                if CompKey('rawequal') then Result := fFunctionAttri;
                                if CompKey('rawget') then   Result := fFunctionAttri;
                                if CompKey('rawset') then   Result := fFunctionAttri;
                                if CompKey('require') then  Result := fFunctionAttri;
                            end;
                    's':    begin
                                if CompKey('select') then   Result := fFunctionAttri;
                                if CompKey('setfenv') then  Result := fFunctionAttri;
                                if CompKey('setmetatable') then Result := fFunctionAttri;
                            end;
                    't':    begin
                                if CompKey('then') then     Result := fKeyAttri;
                                if CompKey('true') then     Result := fKeyAttri;
                                if CompKey('tonumber') then Result := fFunctionAttri;
                                if CompKey('tostring') then Result := fFunctionAttri;
                                if CompKey('type') then     Result := fFunctionAttri;
                            end;
                    'u':    begin
                                if CompKey('until') then    Result := fKeyAttri;
                                if CompKey('unpack') then   Result := fFunctionAttri;
                            end;
                    'w':    if CompKey('while') then    Result := fKeyAttri;
                    'x':    if CompKey('xpcall') then   Result := fFunctionAttri;
                end;
            end;
        3:  Result := fNumberAttri;
    end;
end;

procedure TSynLuaHL.GetTokenEx(out TokenStart: PChar; out TokenLength: integer);
begin
    TokenStart  := @FLine[FTokenPos];
    TokenLength := FTokenEnd - FTokenPos;
end;

function TSynLuaHL.GetTokenKind: integer;
var
    a: TSynHighlighterAttributes;
begin
    a := GetTokenAttribute;
    Result := 0;
    if a = fCommentAttri    then Result := 1;
    if a = fFunctionAttri   then Result := 2;
    if a = fIdentifierAttri then Result := 3;
    if a = fKeyAttri        then Result := 4;
    if a = fNumberAttri     then Result := 5;
    if a = fSpaceAttri      then Result := 6;
    if a = fStringAttri     then Result := 7;
    if a = fSymbolAttri     then Result := 8;
end;

function TSynLuaHL.GetTokenPos: integer;
begin
    Result := FTokenPos - 1;
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
            '-':    if (FLine[FTokenEnd] = '-') then  // it's comment
                    begin
                        Inc(FTokenEnd);
                        if FLine[FTokenEnd] = #0 then exit;
                        if FLine[FTokenEnd] = '[' then
                        begin
                            Inc(FTokenEnd);
                            if not BlockSearchStart(false) then // not a block, just line
                                while (FLine[FTokenEnd] <> #0) do Inc(FTokenEnd);
                            if FCurRange < 0 then FCurRange := 0;
                        end
                        else
                            while (FLine[FTokenEnd] <> #0) do Inc(FTokenEnd);
                    end;

            '[':    BlockSearchStart(true);
            '''':   TextSearchEnd(true);
            '"':    TextSearchEnd(false);
            '{':    StartCodeFoldBlock(nil);
            '}':    EndCodeFoldBlock;
        end;
        exit;
    end;

    if SymTypes[FLine[FTokenEnd]] = 2 then  // ident
    begin
        while (SymTypes[FLine[FTokenEnd]] >= 2) do Inc(FTokenEnd);
        case FLine[FTokenPos] of
            'd': if CompKey('do') then StartCodeFoldBlock(nil);
            'e': begin
                    if CompKey('else') then begin
                        EndCodeFoldBlock;
                        StartCodeFoldBlock(nil);
                    end;
                    if CompKey('elseif') then begin
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

procedure TSynLuaHL.TextSearchEnd(Quote: Boolean);
var
    ch: Char;
begin
    FCurRange := 0;
    if FLine[FTokenEnd] = #0 then exit;
    if Quote then ch := '''' else ch := '"';
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
                if Quote then FCurRange := 1 else FCurRange := 2;
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
