**FREE
ctl-opt option (*srcstmt : *nodebugio : *nounref);
ctl-opt debug (*input);
ctl-opt dftactgrp (*no);
//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
//  Program : Dropbox2
//  Author  : Mike Larsen
//  Date Written: 09/18/2019
//  Purpose : This program will consume a Dropbox web service to
//            download a Csv, Word, or Pdf document.
//
//====================================================================*
//   Date    Programmer  Description                                  *
//--------------------------------------------------------------------*
// 09/18/19  M.Larsen    Original code.                               *
//                                                                    *
//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - *

// - - - -
// Workfields

dcl-s WebServiceUrl      varchar(1024) inz;
dcl-s WebServiceHeader   varchar(1024) ccsid(*utf8) inz;
dcl-s Text               varchar(1000) inz;
dcl-s CmdStr             char(1000);
dcl-s quote              char(6) inz('&quot;');
dcl-s ifs_clob           sqltype(clob:16000000);
dcl-s accessToken        char(200) inz;
dcl-s documentToDownload char(5) inz;

// Dropbox file info - these will be downloaded to Ifs

dcl-s DropboxDocumentName char(150) inz;
dcl-s DropboxCsvDocument  char(150) inz;
dcl-s DropboxPdfDocument  char(150) inz;
dcl-s DropboxWordDocument char(150) inz;

// Ifs file info

dcl-s ifsDirectory    char(25) inz('/home/MLARSEN');
dcl-s fullIfsPath     char(200);

dcl-s ifsDocumentName char(150) inz;
dcl-s ifsCsvDocument  char(150) inz;
dcl-s ifsPdfDocument  char(150) inz;
dcl-s ifsWordDocument char(150) inz;

dcl-s File_Out      Sqltype(Clob_file);

// - - - - - - -

// The SQLTYPE(CLOB_FILE) definition will be converted by the compiler
// into the following data structure:
//
// File_Out        DS
// File_Out_NL                   10U 0
// File_Out_DL                   10U 0
// File_Out_FO                   10U 0
// File_Out_NAME                 255A

// - - - -
// Run CL Command

dcl-pr Run     ExtPgm('QCMDEXC');
       CmdStr  Char(3000) Options(*VarSize);
       CmdLen  Packed(15:5) Const;
       CmdDbcs Char(2) Const Options(*Nopass);
End-pr;

//--------------------------------------------------------

// manually set this for now, but it would be a parm coming in to the program

documentToDownload = 'word';

setup();
getToken();
setupDropboxDocumentVariables();
setupIfsDocumentVariables();

Select;
  When %trim(documentToDownload) = 'csv';
       DropboxDocumentName = DropboxCsvDocument;
       ifsDocumentName     = ifsCsvDocument;

  When %trim(documentToDownload) = 'pdf';
       DropboxDocumentName = DropboxPdfDocument;
       ifsDocumentName     = ifsPdfDocument;

  When %trim(documentToDownload) = 'word';
       DropboxDocumentName = DropboxWordDocument;
       ifsDocumentName     = ifsWordDocument;
Endsl;

setupWebServiceVariables(DropboxDocumentName);
createIfsFile();
consumeWs();
writeDocumentToIfs();

*Inlr = *On;
Return;

//--------------------------------------------------------
// setup subprocedure
//--------------------------------------------------------

dcl-proc setup;

  // - - - -
  // change job's ccsid to 37

  CmdStr = 'CHGJOB CCSID(37)';

  Callp Run(Cmdstr:%Size(CmdStr));

end-proc setup;

//--------------------------------------------------------
// getToken subprocedure
//--------------------------------------------------------

dcl-proc getToken;

  accessToken =
   'YOUR_ACCESS_TOKEN';

end-proc getToken;

//--------------------------------------------------------
// setupDropboxDocumentVariables subprocedure
//--------------------------------------------------------

dcl-proc setupDropboxDocumentVariables;

  DropboxCsvDocument  = '/Apps/Mike Larsen test app/Duplicate NDC numbers.csv';
  DropboxPdfDocument  = '/Apps/Mike Larsen test app/11C_-_Advanced_SQL_DDL_-_+
                         More_than_just_physical_files.pdf';
  DropboxWordDocument = '/Apps/Mike Larsen test app/testWordDoc.docx';

end-proc setupDropboxDocumentVariables;

//--------------------------------------------------------
// setupIfsDocumentVariables subprocedure
//--------------------------------------------------------

dcl-proc setupIfsDocumentVariables;

  ifsCsvDocument  = 'Duplicate NDC numbers.csv';
  ifsPdfDocument  = '11C_-_Advanced_SQL_DDL_-_More_than_just_physical_+
                     files.pdf';

  ifsWordDocument = 'testWordDoc.docx';

end-proc setupIfsDocumentVariables;

//--------------------------------------------------------
// setupWebServiceVariables subprocedure
//--------------------------------------------------------

dcl-proc setupWebServiceVariables;

  dcl-pi *N;
    inDocumentName char(150);
  end-pi;

  // - - - -
  // this could be a soft-coded parameter passed to the program

  WebServiceHeader =

    '<httpHeader> ' +
    '<header name="Authorization" ' +
            'value="Bearer ' + %trim(accessToken) +  '"/> ' +

    '<header name="Accept" +
             value="application/octet-stream; charset=utf-8"/> ' +

    '<header name="Dropbox-API-Arg" ' +
            'value="{' + quote + 'path' + quote + ':' + quote +
                     %trim(inDocumentName) + quote + '}"/> ' +

    '</httpHeader>';

  WebServiceUrl = 'URL_from_Dropbox';

end-proc setupWebServiceVariables;

//--------------------------------------------------------
// createIfsFile subprocedure
//--------------------------------------------------------

dcl-proc createIfsFile;

  // make sure the file name doesn't have spaces in it. If it does, the
  // 'touch' command will create a separate file for each part of the
  // file name that is separated by a space.

  ifsDocumentName = %ScanRpl(' ' : '' : ifsDocumentName);

  CmdStr = *Blanks;

  // Run a shell script to create the file in the Ifs that will hold
  // the document. Using 819 ensures the file is created as Ascii.

  CmdStr = 'Qsh Cmd(''touch -C 819 ' + '/' +
                    %trim(ifsDirectory) + '/' +
                    %trim(ifsDocumentName) + ''')';

  Callp Run(Cmdstr:%Size(CmdStr));

end-proc createIfsFile;

//--------------------------------------------------------
// consumeWs subprocedure
//--------------------------------------------------------

dcl-proc consumeWs;

Exec sql
  Declare CsrC01 Cursor For

    Select
      Systools.HttpGetClob(:WebServiceUrl, :WebServiceHeader)
       from sysibm.sysdummy1;

  Exec Sql Close CsrC01;
  Exec Sql Open  CsrC01;

  DoU 1 = 0;
    Exec Sql
      Fetch Next From CsrC01 into :ifs_clob;

      If SqlCode < *Zeros or SqlCode = 100;

         If SqlCode < *Zeros;
            Exec Sql

              // perform error handling

              Get Diagnostics Condition 1
               :Text = MESSAGE_TEXT;
         EndIf;

         Exec Sql
           Close CsrC01;
           Leave;
      EndIf;

  Enddo;

end-proc consumeWs;

//--------------------------------------------------------
// writeDocumentToIfs subprocedure
//--------------------------------------------------------

dcl-proc writeDocumentToIfs;

  fullIfsPath = '/' + %Trim(ifsDirectory) + '/' + %Trim(ifsDocumentName);

  // set up output parameters.  we'll be taking a document from the Clob field
  // and writing it to the Ifs.

  File_Out_fo   = Sqfovr;
  File_Out_name = %trim(fullIfsPath);
  File_Out_nl   = %Len(%trimR(File_Out_Name));

  // get the data from the Clob field and write it to the Ifs.

  Exec sql
    Select :ifs_clob
     Into :File_Out
     from sysibm.sysdummy1;

end-proc writeDocumentToIfs;

//- - - - - - - - - - - - - - 