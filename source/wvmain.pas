unit wvMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, ShellCtrls,
  ComCtrls, StdCtrls, TAGraph, TASeries, TATools, TAChartListbox, MPHexEditor,
  wvWav;

type

  { TMainForm }

  TMainForm = class(TForm)
    Chart: TChart;
    ChartListbox1: TChartListbox;
    ChartToolset1: TChartToolset;
    ChartToolset1PanDragTool1: TPanDragTool;
    ChartToolset1ZoomDragTool1: TZoomDragTool;
    ChartToolset1ZoomMouseWheelTool1: TZoomMouseWheelTool;
    edAudioFormat: TEdit;
    edBlockAlign: TEdit;
    edBitsPerSample: TEdit;
    edByteValue: TEdit;
    edShortIntValue: TEdit;
    edCurrentOffset: TEdit;
    edWordValue: TEdit;
    edSmallIntValue: TEdit;
    edLongIntValue: TEdit;
    edLongWordValue: TEdit;
    edNumChannels: TEdit;
    edSampleRate: TEdit;
    edByteRate: TEdit;
    FilesPanel: TPanel;
    ImageList: TImageList;
    Label1: TLabel;
    Label10: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Label8: TLabel;
    Label9: TLabel;
    lblFormulaByteRate: TLabel;
    lblFormulaBlockAlign: TLabel;
    lblAudioFormat: TLabel;
    lblBlockAlign: TLabel;
    lblBitsPerSample: TLabel;
    lblNumChannels: TLabel;
    lblSampleRate: TLabel;
    lblByteRate: TLabel;
    PageControl1: TPageControl;
    Panel1: TPanel;
    Panel2: TPanel;
    ShellListView: TShellListView;
    ShellTreeView: TShellTreeView;
    Splitter1: TSplitter;
    Splitter2: TSplitter;
    pgHeader: TTabSheet;
    pgChart: TTabSheet;
    pgHex: TTabSheet;
    Splitter3: TSplitter;
    Splitter4: TSplitter;
    procedure FormCreate(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure ShellListViewSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
    procedure ShellTreeViewGetImageIndex(Sender: TObject; Node: TTreeNode);
    procedure ShellTreeViewGetSelectedIndex(Sender: TObject; Node: TTreeNode);

  private
    FHeader: TWavFmtSubchunk;
    FFileName: String;
    FBigEndian: Boolean;
    FHexEditor: TMPHexEditor;
    function ReadFormat(AStream: TStream): Boolean;
    function ReadHeader(AStream: TStream): Boolean;
    function ReadSamples(AStream: TStream): Boolean;
    procedure ResetDisplay;

    procedure HexSelectionChangedHandler(Sender: TObject);
  public
    procedure OpenWavFile(const AFileName: String);

  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

uses
  wvGlobal;

const
  COLORS: array[0..3] of TColor = (clRed, clBlue, clBlack, clFuchsia);

  WAV_FORMAT_ERROR = 'File "%s" is not a valid WAV file.';
  DAMAGED_FILE_ERROR = 'File "%s" is damaged.';


{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := PROGRAM_NAME;
  ShellListview.Mask := '*.wav';

  FHexEditor := TMPHexEditor.Create(self);
  FHexEditor.Parent := pgHex;
  FHexEditor.Align := alClient;
  FHexEditor.BorderSpacing.Around := 6;
  FHexEditor.Font.Size := 10;
  FHexEditor.ReadOnlyView := true;
  FHexEditor.ReadOnlyFile := true;
  FHexEditor.ShowRuler := true;
  FHexEditor.BytesPerColumn := 1;
  FHexEditor.OnSelectionChanged := @HexSelectionChangedHandler;

  ChartToolset1ZoomMouseWheelTool1.Zoomfactor := 1.1;
  ChartToolset1ZoomMouseWheelTool1.ZoomRatio := 1.0/ChartToolset1ZoomMouseWheelTool1.Zoomfactor;

  if (ParamCount > 0) then begin
    ShellListView.Root := ParamStr(1);
    ShellTreeView.Path := ParamStr(1);
  end;
end;


procedure TMainForm.FormDropFiles(Sender: TObject;
  const FileNames: array of string);
begin
  OpenWavFile(FileNames[0]);
end;


procedure TMainForm.HexSelectionChangedHandler(Sender: TObject);
var
  P: Int64;
  b: Byte;
  w: Word;
  lw: LongWord;
begin
  P := FHexEditor.GetCursorPos;

  edCurrentOffset.Text := IntToStr(P);

  if P + 1 < FHexEditor.DataSize then
  begin
    FHexEditor.ReadBuffer(b, P, 1);
    edByteValue.Text := IntToStr(b);
    edShortIntValue.Text := IntToStr(ShortInt(b));
  end else
  begin
    edByteValue.Text := '';
    edShortIntvalue.Text := '';
  end;

  if P + 2 < FHexEditor.DataSize then
  begin
    FHexEditor.ReadBuffer(w, P, 2);
    if FBigEndian then w := BEToN(w);
    edWordValue.Text := IntToStr(w);
    edSmallIntValue.Text := IntToStr(SmallInt(w));
  end else
  begin
    edWordValue.Text := '';
    edSmallIntValue.Text := '';
  end;

  if P + 4 < FHexEditor.DataSize then
  begin
    FHexEditor.ReadBuffer(lw, P, 4);
    if FBigEndian then lw := BEToN(lw);
    edLongWordValue.Text := IntToStr(lw);
    edLongIntValue.Text := IntToStr(LongInt(lw));
  end else
  begin
    edLongWordvalue.Text := '';
    edLongIntvalue.Text := '';
  end;
end;

procedure TMainForm.OpenWavFile(const AFileName: String);
var
  stream: TStream;
begin
  stream := TMemoryStream.Create;
  try
    FFileName := AFileName;
    TMemoryStream(stream).LoadFromFile(AFileName);

    // Update information in form
    Caption := Format('%s - %s', [PROGRAM_NAME, ExtractFileName(FFilename)]);

    // Reset Header tag
    ResetDisplay;

    // Load into hex editor
    FHexEditor.LoadFromStream(stream);

    // Read and check RIFF header
    stream.Position := 0;
    if not ReadFormat(stream) then
      exit;

    // Read Subchunk header
    if not ReadHeader(stream) then
      exit;

    // Read samples
    if not ReadSamples(stream) then
    begin
      Chart.ClearSeries;
      exit;
    end;
  finally
    stream.Free;
  end;
end;


function TMainForm.ReadFormat(AStream: TStream): Boolean;
var
  riff: TWavRiffHeader;
begin
  Result := false;

  if AStream.Read(riff{%H-}, SizeOf(riff)) <> SizeOf(riff) then
  begin
    MessageDlg(Format(DAMAGED_FILE_ERROR, [FFileName]), mtError, [mbOK], 0);
    exit;
  end;

  if not (riff.ID[0] = 'R') and (riff.ID[1] = 'I') and (riff.ID[2] = 'F') then
  begin
    MessageDlg(Format(WAV_FORMAT_ERROR, [FFileName]), mtError, [mbOk], 0);
    exit;
  end;

  if riff.ID[3] = 'F' then       // 'RIFF' --> little endian
    FBigEndian := false
  else if riff.ID[3] = 'X' then  // 'RIFX' --> big endian
    FBigEndian := true
  else
  begin
    MessageDlg(Format(WAV_FORMAT_ERROR, [FFileName]), mtError, [mbOk], 0);
    exit;
  end;

  if not ((riff.RiffType[0]='W') and (riff.RiffType[1]='A') and (riff.RiffType[2]='V') and (riff.RiffType[3]='E')) then
  begin
    MessageDlg(Format(WAV_FORMAT_ERROR, [FFileName]), mtError, [mbOK], 0);
    exit;
  end;

  Result := true;
end;


function TMainForm.ReadHeader(AStream: TStream): Boolean;
begin
  Result := false;

  if AStream.Read(FHeader, SizeOf(FHeader)) <> SizeOf(FHeader) then begin
    MessageDlg(Format(DAMAGED_FILE_ERROR, [FFileName]), mtError, [mbOK], 0);
    exit;
  end;

  if not ((FHeader.ID[0]='f') and (FHeader.ID[1]='m') and (FHeader.ID[2]='t') and (FHeader.ID[3]=' ')) then
  begin
    MessageDlg(Format(WAV_FORMAT_ERROR, [FFileName]), mtError, [mbOK], 0);
    exit;
  end;

  if FBigEndian then
  begin
    FHeader.SubChunkSize := BEToN(FHeader.SubChunkSize);
    FHeader.AudioFormat := BEToN(FHeader.AudioFormat);
    FHeader.NumChannels := BEToN(FHeader.NumChannels);
    FHeader.SampleRate := BEToN(FHeader.SampleRate);
    FHeader.ByteRate := BEToN(FHeader.ByteRate);
    FHeader.BitsPerSample := BEToN(FHeader.BitsPerSample);
  end;

  // Display header information
  if FHeader.AudioFormat = 1 then
    edAudioFormat.Text := 'PCM (uncompressed)'
  else
    edAudioFormat.Text := '[not supported]';
  edNumChannels.Text := IntToStr(FHeader.NumChannels);
  edSampleRate.Text := IntToStr(FHeader.SampleRate);
  edByteRate.Text := IntToStr(FHeader.ByteRate);
  edBlockAlign.Text := IntToStr(FHeader.BlockAlign);
  edBitsPerSample.Text := IntToStr(FHeader.BitsPerSample);

  if not (FHeader.BitsPerSample in [8, 16]) then
  begin
    MessageDlg('Bits per sample supported only with values 8 or 16.', mtError, [mbOk], 0);
    exit;
  end;

  Result := true;
end;


function TMainForm.ReadSamples(AStream: TStream): Boolean;
var
  data: TWavDataSubChunk;
  ser: array of TLineSeries;
  channel: Integer;
  numSamples: Integer;
  sampleCounter: Integer;
  t: Double;
  buffer8: ShortInt;
  buffer16: SmallInt;
  P: Int64;

  function IsData: Boolean;
  begin
    Result := (data.ID[0]='d') and (data.ID[1]='a') and (data.ID[2]='t') and (data.ID[3]='a');
  end;

begin
  Result := false;

  repeat
    P := AStream.Position;
    if AStream.Read(data, SizeOf(data)) <> SizeOf(data) then
    begin
      MessageDlg(Format(DAMAGED_FILE_ERROR, [FFileName]), mtError, [mbOK], 0);
      exit;
    end;
    if AStream.Position >= AStream.Size then begin
      MessageDlg(Format(WAV_FORMAT_ERROR, [FFileName]), mtError, [mbOK], 0);
      exit;
    end;

    if FBigEndian then
      data.DataSize := BEToN(data.DataSize);

    if IsData then
      break
    else
      AStream.Position := P + 8 + data.DataSize;
  until false;

  // Create chart
  Chart.ClearSeries;
  SetLength(ser, FHeader.NumChannels);
  for channel := 0 to FHeader.NumChannels-1 do
  begin
    ser[channel] := TLineSeries.Create(Chart);
    ser[channel].Title := 'Channel ' + IntToStr(channel);
    ser[channel].SeriesColor := COLORS[Chart.SeriesCount mod Length(COLORS)];
    ser[channel].ListSource.BeginUpdate;
    Chart.AddSeries(ser[channel]);
  end;
  Chart.Legend.Visible := FHeader.NumChannels > 1;

  // Read samples and add them to the chart.
  numSamples := (data.DataSize * 8) div FHeader.BitsPerSample;
  sampleCounter := 0;
  channel := 0;
  while (sampleCounter < numSamples) do begin
    if not odd(samplecounter) then
      t := sampleCounter/FHeader.SampleRate * 1000;
    case FHeader.BitsPerSample of
       8: begin
            if AStream.Read(buffer8, SizeOf(buffer8)) <> SizeOf(buffer8) then
            begin
              MessageDlg(Format('Sample #%d could not be read completely. Aborting.', [sampleCounter]), mtError, [mbOK], 0);
              exit;
            end;
            ser[channel].AddXY(t, buffer8);
          end;
      16: begin
            if Astream.Read(buffer16, SizeOf(buffer16)) <> SizeOf(buffer16) then
            begin
              MessageDlg(Format('Sample #%d could not be read completely. Aborting.', [sampleCounter]), mtError, [mbOK], 0);
              exit;
            end;
            if FBigEndian then buffer16 := BEToN(buffer16);
            ser[channel].AddXY(t, buffer16);
          end;
    end;
    inc(channel);
    if channel = FHeader.NumChannels then channel := 0;
    inc(sampleCounter);
  end;

  for channel := 0 to High(ser) do
    ser[channel].ListSource.EndUpdate;

  Result := true;
end;


procedure TMainForm.ResetDisplay;
begin
  edAudioFormat.Text := '';
  edNumChannels.Text := '';
  edSampleRate.Text := '';
  edBitsPerSample.Text := '';
  edByteRate.Text := '';
  edBlockAlign.Text := '';

  Chart.ClearSeries;
end;


procedure TMainForm.ShellListViewSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
var
  fn: String;
begin
  if Selected then
  begin
    fn := ShellListview.GetPathFromItem(ShellListview.Selected);
    ShellTreeview.MakeSelectionVisible;
    OpenWavFile(fn);
  end;
end;

procedure TMainForm.ShellTreeViewGetImageIndex(Sender: TObject; Node: TTreeNode);
begin
  Node.ImageIndex := 0;
end;

procedure TMainForm.ShellTreeViewGetSelectedIndex(Sender: TObject; Node: TTreeNode);
begin
  Node.SelectedIndex := 1;
end;

end.

