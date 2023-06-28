unit main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ComCtrls,
  Buttons, Menus, Windows, ActiveX, ShlObj, sqlite3conn, sqldb, lazpng, comobj
  , lazfileutils, db, BufDataSet, shellapi
  , renametab
  , tapp, tdb, tmsg, tstr, tlib
  ;

type

  { TfmMain }

  TfmMain = class(TForm)
    miRemoveButton: TMenuItem;
    miRemoveTab: TMenuItem;
    miRenameTab: TMenuItem;
    miAddTab: TMenuItem;
    NoteBook: TPageControl;
    pmTabs: TPopupMenu;
    pmButtons: TPopupMenu;
    sqlite3: TSQLite3Connection;
    qrMain: TSQLQuery;
    trsMain: TSQLTransaction;
    StatusBar1: TStatusBar;
    procedure FormActivate(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of String);
    procedure FormKeyDown(Sender: TObject; var Key: Word; {%H-}Shift: TShiftState);
    procedure miAddTabClick(Sender: TObject);
    procedure miRemoveButtonClick(Sender: TObject);
    procedure miRemoveTabClick(Sender: TObject);
    procedure miRenameTabClick(Sender: TObject);
  private

    const
      csDatabaseFileName = 'leasylauncher.db';
      ciHeight           = 36;
      ciWidth            = 35;
      ciSpaceLength      = 2;

    procedure createDatabaseIfNeeded();
    procedure addLink(psFileName : String);
    procedure addExe(psExeName : String);
    procedure addOther(psFileName : String);
    function  extractExeFileSpecFromLink(psLinkName : String) : String;
    function  extractIconFromExe(psExeName: String) : TPNGImage;
    function  GetAssociatedIcon(const psFileName: string): TPNGImage;
    //procedure extractAndSaveIconFromExeFile(psExeName, psIconName : String);
    procedure OnClick(Sender : TObject);
    procedure loadTabs();
    procedure buttonHandler(Sender: TObject);
    procedure addButton(piLeft : Integer);
  public

  end;

const csSQLSelectAll: String = 'select   TB.id as atabid' + #10 +
                       '       , TB.fname as atabname' + #10 +
 		                   '       , BT.id as abuttonid' + #10 +
		                   '       , BT.fname as abuttonname' + #10 +
		                   '       , BT.ffullpath as abuttonapppath' + #10 +
		                   '       , BT.ficon as abuttonicon' + #10 +
		                   '       , BT.fposition as abuttonposition' + #10 +
		                   '  from tbltabs TB' + #10 +
		                   '  left join tblbuttons BT' + #10 +
		                   '    on     (BT.ftabid=TB.id)' + #10 +
		                   '       and (BT.fstatus>0)' + #10 +
		                   '  where TB.fstatus>0' + #10 +
		                   '  order by TB.id, BT.fposition'+#10;
      SHGFI_LARGEICON         = $000000000;
var
  fmMain: TfmMain;

implementation

{$R *.lfm}

{
 * Добавить Exe-файл
 * Добавить произвольный файл
 * Удалить кнопку
 * Поменять кнопки местами
 * Добавить вкладку
 * Переименовать вкладку
 * Удалить вкладку
 * Поменять вкладки местами
}

{ **** UBPFD *********** by delphibase.endimus.com ****
>> Получение системной иконки, ассоциированной с файлом в данной системе

Функция позволяет получить такую же иконку любой директории или любого файла,
какую вы видите в "проводнике". Размеры - 16 * 16 (по умолчанию) или 32 * 32
(второй параметр - itLarge)

Зависимости: Юниты VCL + ComObj, ActiveX, ShellApi, ShlObj;
Автор:       Дмитрий Баранов, kda@pisem.net, Москва
Copyright:   Взято из MSDN
Дата:        20 мая 2002 г.
***************************************************** }

type
  TIconType = (itSmall, itLarge);

function TfmMain.GetAssociatedIcon(const psFileName: string): TPNGImage;
var loInfoFile : SHFILEINFO;
    lcFlag : Cardinal;
    loIcon : TIcon;
    loPNG : TPNGImage;
begin

  loPNG := TPngImage.Create();
  try

    lcFlag:=SHGFI_ICON or SHGFI_LARGEICON;
    ZeroMemory(Addr(loInfoFile),SizeOf(loInfoFile));
    SHGetFileInfo(PAnsiChar(psFileName),0,loInfoFile,SizeOf(loInfoFile),lcFlag);
    loIcon := TIcon.Create;
    loIcon.Handle := loInfoFile.iIcon;
    loPNG.Assign(loIcon);
  finally

     FreeAndNil(loIcon);
  end;
  Result := loPNG;
end;

{ TfmMain }

procedure TfmMain.FormDropFiles(Sender: TObject; const FileNames : array of String);
var lsFileName  : String;
    lsExtension : String;
begin

  // *** Хоть что-то кинули?
  if Length(FileNames) > 0 then
  begin

    // *** Агааа...
    lsFileName := LowerCase(FileNames[0]);
    lsExtension := ExtractFileExt(lsFileName);
    if lsExtension = '.lnk' then
    begin

      addLink(lsFileName);
    end else
    begin

      if lsExtension='.exe' then
      begin

        addExe(lsFileName);
      end else
      begin

        addOther(lsFileName);
      end;
    end;
  end;
end;


procedure TfmMain.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin

  if Key = VK_ESCAPE then
  begin

    Close;
	end;
end;


procedure TfmMain.miAddTabClick(Sender: TObject);
var loTab      : TTabSheet;
    lsSQL      : String;
    liDoubles  : Integer;
    lblSuccess : Boolean;
begin

  if fmRenameTab.ShowModal = mrOk then
  begin

    try

      lblSuccess := True;
      // *** Проверим, нет ли у нас уже вкладки с таким именем
      lsSQL :=
        'select count("fname") as acount' + #10 +
        '  from "tbltabs"' + LF +
        '  where ("fname" like '+
        APOSTROPHE + PERCENT +
        Trim(fmRenameTab.edTitle.Text)+
        PERCENT + APOSTROPHE +
        ') and ("fstatus">0)';
      initializeQuery(qrMain, lsSQL);
      qrMain.Open;
      liDoubles := qrMain.FieldByName('acount').AsInteger;
      qrMain.Close;
    except

      on E : Exception do
      begin

        lblSuccess := False;
        trsMain.Rollback;
        fatalError('Ошибка!',E.Message);
      end;
    end;
    // *** И?...
    if lblSuccess then
    begin

      if liDoubles > 0 then
      begin

        fatalError('Ошибка!', 'Вкладка с таким названием уже сушествует!');
      end else
      begin

        try

          // *** Нету. Добавляем.
          lsSQL :=
          'insert into "tbltabs" (' + LF +
          '  "fname", "fstatus"' + LF +
          ') values (' + LF +
          ' :pname,1' + LF +
          ');';
          initializeQuery(qrMain,lsSQL);
          qrMain.ParamByName('pname').AsString := fmRenameTab.edTitle.Text;
          qrMain.ExecSQL;
          trsMain.Commit;
        except

          on E : Exception do
          begin

            lblSuccess := False;
            trsMain.Rollback;
            fatalError('Ошибка, не удалось добавить вкладку! ',E.Message);
          end;
        end;
        if lblSuccess then
        begin

          try
            // *** Получаем ID добавленной вкладки
            lsSQL :=
              'select id' + LF +
              '  from tbltabs' + LF +
              '  where rowid=last_insert_rowid();';
            initializeQuery(qrMain,lsSQL);
            qrMain.Open;
            // *** Добавляем вкладку в блокнот и сохраняем ID вкладки в тег
            loTab := NoteBook.AddTabSheet();
            loTab.Caption := fmRenameTab.edTitle.Text;
            loTab.Tag := qrMain.FieldByName('id').AsInteger;
            loTab.PopupMenu := pmTabs;
            NoteBook.ActivePage := loTab;
            qrMain.Close;
          except

            on E : Exception do
            begin

              trsMain.Rollback;
              fatalError('Ошибка!',E.Message);
            end;
          end;
        end;
      end;
    end;
  end;
end;


procedure TfmMain.miRemoveButtonClick(Sender: TObject);
{$region}

{$EndRegion}
var lsSQL     : String;
    loBtn     : TSpeedButton;
    liControl : Integer;
    liControlIdx : Integer;
begin

  loBtn := (pmButtons.PopupComponent as TSpeedButton);

  liControlIdx := -1;
  for liControl := 0 to (NoteBook.ActivePage.ControlCount - 1) do
  begin

    if NoteBook.ActivePage.Controls[liControl] = loBtn then
    begin

      liControlIdx := liControl;
      break;
    end;
  end;

  if liControlIdx >= 0 then
  begin

    for liControl := liControlIdx + 1 to (NoteBook.ActivePage.ControlCount - 1) do
    begin

      if NoteBook.ActivePage.Controls[liControl] is TSpeedButton then
      begin

        loBtn := (NoteBook.ActivePage.Controls[liControl] as TSpeedButton);
        if loBtn.Left > ciSpaceLength then
        begin

          loBtn.Left := (loBtn.Left-ciWidth)-ciSpaceLength;
        end;
      end;
    end;
  end;

  loBtn := (pmButtons.PopupComponent as TSpeedButton);
  lsSQL :=
    'update "tblbuttons"' + LF +
    '  set "fstatus" = 0' + LF +
    '  where "id" = :pid';
  try

    initializeQuery(qrMain,lsSQL);
    qrMain.ParamByName('pid').AsInteger := loBtn.Tag;
    qrMain.ExecSQL;
    trsMain.Commit;
    lsSQL :=
      'select ficonname' + LF +
      '  from tblbuttons' + LF +
      '  where id=:pid';
    initializeQuery(qrMain,lsSQL);
    qrMain.ParamByName('pid').AsInteger := loBtn.Tag;
    qrMain.Open;
    //EasyDeleteFile(getAppFolder()+csIconFolder+qrMain.FieldByName('ficonname').AsString);
    qrMain.Close;
    NoteBook.ActivePage.RemoveControl(loBtn);
    FreeAndNil(loBtn);
    { TODO : Вот тут нужно сдвинуть все кнопки за удалённой влево на ciWidth+1 }

  except

    on E : Exception do
    begin

      trsMain.Rollback;
      fatalError('Ошибка!',E.Message);
    end;
  end;
end;


procedure TfmMain.miRemoveTabClick(Sender: TObject);
begin

  //
end;


procedure TfmMain.miRenameTabClick(Sender: TObject);
var liDoubles : Integer;
    lsSQL     : String;
begin

  try

    fmRenameTab.edTitle.Text := NoteBook.ActivePage.Caption;
    if fmRenameTab.ShowModal = mrOk then
    begin

      lsSQL:=
        'select count(fname) as acount' + LF +
        '  from tbltabs' + LF +
        '  where (fname like :pname' + //APOSTROPHE + PERCENT +
        //Trim(fmRenameTab.edTitle.Text) +
        //PERCENT + APOSTROPHE +
        ') and ("fstatus">0)';

      initializeQuery(qrMain, lsSQL);
      qrMain.ParamByName('pname').AsString :=
        APOSTROPHE + PERCENT +
        Trim(fmRenameTab.edTitle.Text) +
        PERCENT + APOSTROPHE;
      qrMain.Open;
      liDoubles := qrMain.FieldByName('acount').AsInteger;
      qrMain.Close;

      if liDoubles = 0 then
      begin

        lsSQL:=
          'update tbltabs' + LF +
          '   set fname = :pname' + LF +
          ' where id = :pid';
        initializeQuery(qrMain, lsSQL);
        qrMain.ParamByName('pname').AsString := Trim(fmRenameTab.edTitle.Text);
        qrMain.ParamByName('pid').AsInteger := NoteBook.ActivePage.Tag;
        qrMain.ExecSQL;
        trsMain.Commit;
        NoteBook.ActivePage.Caption := fmRenameTab.edTitle.Text;
      end;
    end;
  except

    on E : Exception do
    begin

      trsMain.Rollback;
      fatalError('Ошибка!', E.Message);
    end;
  end;
end;


procedure TfmMain.FormActivate(Sender: TObject);
begin

  OnActivate := Nil;
  createDatabaseIfNeeded();
  loadTabs();
end;


procedure TfmMain.addLink(psFileName: String);
var lsExeName : String;
begin

  lsExeName := extractExeFileSpecFromLink(psFileName);
  {ToDo: вытащить иконку из ярлыка!}
  addExe(lsExeName);
end;


procedure TfmMain.addExe(psExeName: String);
var lsSQL      : String;
    liMax,
    liCount    : Integer;
    loPNG      : TPNGImage;
    loStream   : TStream;
begin

   // *** Вытащим из Exe-файла иконку и сохраним в поток
   loPNG := extractIconFromExe(psExeName); //, lsIconSpec
   loStream := TMemoryStream.Create();
   loPNG.SaveToStream(loStream);
   loStream.Seek(0, soFromBeginning);
   // *** Получим количество иконок на странице
   try

     lsSQL :=
       'select min(fposition) as amin,' + LF +
       '       max(fposition) as amax,' + LF +
       '       count(fposition) as acount' + LF +
       '  from (' + LF +
       '    select fposition'+ LF +
       '      from tblbuttons'+ LF +
       '      where (ftabid=:ptabid) and (fstatus>0)' + LF +
       '  ) subquery';
     initializeQuery(qrMain,lsSQL);
     qrMain.ParamByName('ptabid').AsInteger := NoteBook.ActivePage.Tag;
     qrMain.Open;
     qrMain.First;
     if (not qrMain.FieldByName('acount').IsNull) and
        (qrMain.FieldByName('acount').AsInteger > 0) then
     begin

       //liMin := qrMain.FieldByName('amin').AsInteger;
       liMax := qrMain.FieldByName('amax').AsInteger;
       liCount := qrMain.FieldByName('acount').AsInteger;
     end else
     begin

       //liMin := 1;
       liMax := 1;
       liCount := 0;
     end;
     qrMain.Close;

     // *** Добавим новую иконку.
     lsSQL:=
       'insert into tblbuttons (' + LF +
       '    ftabid, fposition, fname, ffullpath' + LF +
       '  , farguments, ficonname, ficon, fstatus' + LF +
       '  ) values (' + LF +
       '    :ptabid, :pposition, :pname, :pfullpath' + LF +
       '  , :pargument, "1", :picon, 1' + LF +
       '  )';
     initializeQuery(qrMain,lsSQL);
     qrMain.ParamByName('ptabid').AsInteger := NoteBook.ActivePage.Tag;
     qrMain.ParamByName('pposition').AsInteger := liMax+1;
     qrMain.ParamByName('pname').AsString := ExtractFileNameWithoutExt(ExtractFileName(psExeName));
     qrMain.ParamByName('pfullpath').AsString := psExeName;
     qrMain.ParamByName('pargument').AsString := '';
     qrMain.ParamByName('picon').LoadFromStream(loStream, ftBlob);
     qrMain.ExecSQL;
     trsMain.Commit;

     lsSQL:=
       'select   "id" as abuttonid'#13+
       '       , "fname" as abuttonname'#13+
       '       , "ffullpath" as abuttonapppath'#13+
       '       , "ficon" as abuttonicon'#13+
       '  from "tblbuttons"'#13+
       '  where     ("ftabid"=:ptabid)'#13+
       '        and ("fposition"=:pposition)';
     initializeQuery(qrMain,lsSQL);
     qrMain.ParamByName('ptabid').AsInteger := NoteBook.ActivePage.Tag;
     qrMain.ParamByName('pposition').AsInteger := liMax + 1;
     qrMain.Open;
     qrMain.First;
     addButton((liCount) * (ciWidth + 1));
     qrMain.Close;
   except

     on E : Exception do
     begin

       trsMain.Rollback;
       fatalError('Ошибка!',E.Message);
     end;
   end;
end;


procedure TfmMain.addOther(psFileName: String);
begin

  //
end;


function TfmMain.extractExeFileSpecFromLink(psLinkName: String): String;
var loInterface : IUnknown;
    loShellLink : IShellLink;
    loPersFile  : IPersistFile;
    loFileInfo  : TWin32FINDDATA;
    lwcWidePath : array[0..MAX_PATH] of WideChar;
    lcBuff      : array[0..MAX_PATH] of Char;
begin

  loInterface := CreateComObject(CLSID_ShellLink);
  loPersFile := loInterface as IPersistFile;
  loShellLink := loInterface as IShellLink;
  StringToWideChar(psLinkName, lwcWidePath, SizeOf(lwcWidePath));
  loPersFile.Load(lwcWidePath, STGM_READ);
  loShellLink.GetPath(lcBuff, MAX_PATH, loFileInfo{%H-}, SLGP_UNCPRIORITY);
  Result := lcBuff;
end;

(*
procedure TfmMain.extractAndSaveIconFromExeFile(psExeName, psIconName: String);
var loIcon        : TIcon;
    lhIcon        : HIcon;
    loPNG         : TPngImage;
begin

  lhIcon := ExtractIconA(HINSTANCE, @psExeName[1],0);
  loIcon := TIcon.Create;
  try

    loIcon.Handle := lhIcon;
    loPNG := TPngImage.Create();
    loPNG.Assign(loIcon);
    loPNG.SaveToFile(psIconName);
  finally
    DestroyIcon(lhIcon);
    loIcon.Free;
    loPNG.Free;
  end;
end;
*)

function TfmMain.extractIconFromExe(psExeName : String) : TPNGImage;
var loIcon        : TIcon;
    lhIcon        : HIcon;
    loPNG         : TPNGImage;
begin

  Result := Nil;
  lhIcon := ExtractIconA(HINSTANCE, @psExeName[1],0);
  loIcon := TIcon.Create;
  try

    loIcon.Handle := lhIcon;
    loPNG := TPngImage.Create();
    loPNG.Assign(loIcon);
    Result := loPNG;
  finally
    DestroyIcon(lhIcon);
    loIcon.Free;
  end;
end;


procedure TfmMain.OnClick(Sender: TObject);
//const csSQL = 'select ffullpath from tblbuttons where id = :pid';
var loButton : TSpeedButton;
    lsPath: String;
begin

  if Sender is TSpeedButton then
  begin

    loButton := Sender as TSpeedButton;
    initializeQuery(qrMain, csSQLSelectAll);
    qrMain.Open;
    qrMain.Last;
    qrMain.First;
    if qrMain.Locate('abuttonid', loButton.Tag{%H-}, []) then
    begin

		  lsPath:=qrMain.FieldByName('abuttonapppath').AsString;
		  EasyExec(lsPath, '', False);
		end;
	end;
end;


procedure TfmMain.loadTabs();
var liTabID : Integer;
    loTab   : TTabSheet;
    liLeft  : Integer;
begin

  try

    // *** Запросим данные
    initializeQuery(qrMain, csSQLSelectAll);
    qrMain.Open;
    qrMain.First;
    // *** Поехали!
    liTabID := -1;
    // ! Сдвиг новой кнопки относительно левого края таблицы
    liLeft := 1;
    while not qrMain.EOF do
    begin

      // *** Вкладка та же самая еще?
      if liTabID <> qrMain.FieldByName('atabid').AsInteger then
      begin

        // *** Нет. Добавляем новую вкладку
        liTabID := qrMain.FieldByName('atabid').AsInteger;
        loTab := NoteBook.AddTabSheet();
        loTab.Caption := qrMain.FieldByName('atabname').AsString;
        loTab.Tag := liTabID;
        loTab.PopupMenu := pmTabs;
        NoteBook.ActivePage := loTab;
        liLeft := 1;
      end;
      // *** Если есть хоть одна кнопка на этом листе..
      if not qrMain.FieldByName('abuttonname').isNull then
      begin

        // *** Добавляем новую кнопку.
        addButton(liLeft);
        liLeft := liLeft + ciWidth + ciSpaceLength;
        { TODO : Если позиция следующей кнопки находится за пределами листа - прервать вывод }
      end;
      qrMain.Next;
    end;
    qrMain.Close();
  except

    on E : Exception do
    begin

      fatalError('Ошибка!',E.Message);
    end;
  end;
end;


procedure TfmMain.buttonHandler(Sender: TObject);
begin

  with Sender as TSpeedButton do
  begin

    //EasyExec(Caption,'');
  end;
end;


procedure TfmMain.addButton(piLeft: Integer);
var loBtn : TSpeedButton;
    loPNG : TPNGImage;
    loStream: TBufBlobStream;
begin

  loBtn := TSpeedButton.Create(NoteBook.ActivePage);
  loBtn.Left := piLeft;
  loBtn.Top := 1;
  loBtn.Width := ciWidth;
  loBtn.Height := ciHeight;
  loBtn.OnClick := @ButtonHandler;
  loBtn.ShowCaption := False;
  loBtn.ShowHint := False;
  loBtn.PopupMenu := pmButtons;
  loBtn.Tag := qrMain.FieldByName('abuttonid').AsInteger;
  loBtn.Hint := qrMain.FieldByName('abuttonname').AsString;
  loBtn.Caption := qrMain.FieldByName('abuttonapppath').AsString;
  loBtn.Flat := False;
  loBtn.OnClick:=@OnClick;
  loStream := TBufBlobStream(qrMain.CreateBlobStream(qrMain.FieldByName('abuttonicon'),bmRead));
  loPNG := TPNGImage.Create();
  loPNG.LoadFromStream(loStream);
  loBtn.Glyph.Assign(loPNG);
  FreeAndNil(loPNG);
  NoteBook.ActivePage.InsertControl(loBtn);
end;


procedure TfmMain.createDatabaseIfNeeded();
{$region 'SQL'}
const csSQLCreateTabsTable =
        'create table "tbltabs" ('#13+
        '    "id" integer primary key asc on conflict abort'+
        '         autoincrement not null on conflict abort '+
        '         unique on conflict abort,'#13+
        '    "fname" nchar(32) not null on conflict abort,'#13+
        '    "fstatus" integer not null on conflict abort default(1)'#13+
        ');';

      csSQLCreateButtonsTable =
        'create table "tblbuttons" ('#13+
        '    "id" integer primary key asc on conflict abort'+
        '         autoincrement not null on conflict abort '+
        '         unique on conflict abort,'#13+
        '    "ftabid" integer not null on conflict abort,'#13+
        '    "fposition" integer not null on conflict abort,'#13+
        '    "fname" nchar(32) not null on conflict abort,'#13+
        '    "ffullpath" nchar(255) not null on conflict abort,'#13+
        '    "farguments" nchar(255) not null on conflict abort,'#13+
        '    "ficonname" nchar(255) not null on conflict abort,'#13+
        '    "ficon" blob,'#13+
        '    "fstatus" integer not null on conflict abort default(1)'#13+
        ');';

      csSQLAddDefaultTab =
        'insert into "tbltabs" ('#13+
        '  "fname", "fstatus"'#13+
        '  ) values ('#13+
        '  "Default", 1'#13+
        '  )';

      csSQLAddDefaultApp =
        'insert into tblbuttons ('#13+
        '    ftabid, fposition, fname, ffullpath'#13+
        '  , farguments ,ficonname, fstatus'#13+
        '  ) values ('#13+
        '    1, 1, "Notepad","C:/Windows/System32/notepad.exe"'#13+
        '  , "", "notepad.png", 1'#13+
        '  )';
{$endregion}
var lblDatabaseExists : Boolean;
begin

  try

    sqlite3.DatabaseName := getAppFolder()+csDatabaseFileName;
    lblDatabaseExists := FileExists(sqlite3.DatabaseName);
    sqlite3.Open;
    sqlite3.Connected := True;
    if not lblDatabaseExists then
    begin

      trsMain.StartTransaction;
      sqlite3.ExecuteDirect(csSQLCreateTabsTable);
      sqlite3.ExecuteDirect(csSQLCreateButtonsTable);
      sqlite3.ExecuteDirect(csSQLAddDefaultTab);
      sqlite3.ExecuteDirect(csSQLAddDefaultApp);
      trsMain.Commit;
    end;
  except

    on E : Exception do
    begin

      fatalError('Ошибка!',E.Message);
    end;
  end;
end;

(*
procedure TfmMain.GetIconFromLnk(psFileName : String, psIconName: String);
var Icon : TIcon;
    ListItem : TListItem;
    shInfo : TSHFileInfo;
    sFileType : string;
 begin
   { initialise ListView and Icon }
   Icon := TIcon.Create;

   try

     { get details about file type from SHGetFileInfo }
     SHGetFileInfo(PChar(psFileName), 0, shInfo,
       SizeOf(shInfo), SHGFI_TYPENAME);
     sFileType := shInfo.szTypeName;
     if shInfo.szTypeName = 'Shortcut' then
     begin
       SHGetFileInfo(PChar(psFileName), 0, shInfo, SizeOf(shInfo),
         SHGFI_LINKOVERLAY or SHGFI_ICON or
         SHGFI_SMALLICON or SHGFI_SYSICONINDEX)
     end else
     begin

       { ...otherwise treat it as a normal file}
       SHGetFileInfo(PChar(psFileName), 0, shInfo, SizeOf(shInfo),
         SHGFI_ICON or SHGFI_SMALLICON or
         SHGFI_SYSICONINDEX);
     end;
     { assign icon }
     Icon.Handle := shInfo.hIcon;
     Icon.SaveToFile(psIconName);
     { List File name, Icon and FileType in ListView}
  finally

    Icon.Free;
   end;
 end;
*)
end.

