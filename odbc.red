Red [
	Title:   "Red ODBC binding"
	Author:  "Christian Ensel"
	File: 	 %odbc.red
	Rights:  "Copyright (C) 2019 Christian 'che' Ensel. All rights reserved."
	License: "BSD-3 - https://github.com/red/red/blob/master/BSD-3-License.txt"

    Issues: {
        - insufficient error handling
        - incomplete parameter binding and datatype conversion
        - ugly int16 / sqlsmallint handling
        - hacky buggy utf8/16 / (w/t)char / unicode handling
        - Windows support only
        - no pure Red/System API, usable only from Red
    }
]

#system [
    #include %odbc.reds

    #define SET_INT16(int16 value) [
        int16/lo: as byte! value and FFh
        int16/hi: as byte! value >> 8 and FFh
        int16
    ]

    #define GET_INT16(int16) [
        ((as integer! int16/hi) << 8 or (as integer! int16/lo))
    ]

    #define ODBC_DEBUG          comment
    #define ODBC_DEBUG_BYTES    comment
   ;#define ODBC_DEBUG          print
   ;#define ODBC_DEBUG_BYTES    print-bytes

    #define DESCRIBE_ERROR(handle value) [
        diagnose-error handle value
        return as red-value! logic/box false
    ]

    odbc: context [

        ;------------------------------------------------------------ structs --
        ;

        environment!: alias struct! [
            henv        [sql-handle!]
            conn-cnt    [integer!]                                              ;-- if the number of open connections reaches zero,
                                                                                ;   the environment handle can be closed
        ]

        environment: declare environment!

        connection!: alias struct! [
            hdbc        [sql-handle!]
            dsn         [c-string!]
        ]

        column!: alias struct! [
            name        [c-string!]
            name-length [integer!]
            buffer      [byte-ptr!]
            buffer-size [integer!]
            sql-type    [integer!]
            column-size [integer!]
            digits      [integer!]
            nullable    [integer!]
            strlen-ind  [integer!]
            size        [sqlsmallint! value]
            c-type      [sqlsmallint! value]
        ]

        param!: alias struct! [
            buffer      [byte-ptr!]
        ]

        statement!: alias struct! [
            connection  [byte-ptr!]
            hstmt       [sql-handle!]
            columns     [column!]
            columns-cnt [integer!]
            params      [param!]
            params-cnt  [integer!]
        ]


        ;-------------------------------------------------------- print-bytes --
        ;

        print-bytes: func [
            bytes   [byte-ptr!]
            cnt     [integer!]
            /local
                byte hi lo
        ][
            loop cnt [
                byte: bytes/1
                hi:   as integer! ((byte and #"^(F0)") >>> 4)
                lo:   as integer!   byte and #"^(0F)"
                switch hi [
                     0 [print "0"]  1 [print "1"]  2 [print "2"]  3 [print "3"]
                     4 [print "4"]  5 [print "5"]  6 [print "6"]  7 [print "7"]
                     8 [print "8"]  9 [print "9"] 10 [print "a"] 11 [print "b"]
                    12 [print "c"] 13 [print "d"] 14 [print "e"] 15 [print "f"]
                ]
                switch lo [
                     0 [print "0"]  1 [print "1"]  2 [print "2"]  3 [print "3"]
                     4 [print "4"]  5 [print "5"]  6 [print "6"]  7 [print "7"]
                     8 [print "8"]  9 [print "9"] 10 [print "a"] 11 [print "b"]
                    12 [print "c"] 13 [print "d"] 14 [print "e"] 15 [print "f"]
                ]
                print " "
                bytes: bytes + 1
            ]
            print lf
        ]


        ;--------------------------------------------------- open-environment --
        ;

        open-environment: func [
            return:    [logic!]
            /local
                result
        ][
            ODBC_DEBUG ["OPEN-ENVIRONMENT" lf]

            unless environment/henv = null [return true]

            ;-- Allocate an environment handle
            ;
            result: result-of SQLAllocHandle SQL_HANDLE_ENV
                                             null
                                             as byte-ptr! :environment/henv     ODBC_DEBUG ["SQLAllocHandle " result lf]
                                                                                if result = SQL_ERROR [
                                                                                    diagnose-error SQL_HANDLE_ENV environment/henv
                                                                                    return false
                                                                                ]
            ;-- set SQL_ATTR_ODBC_VERSION environment attribute.
            ;
            result: result-of SQLSetEnvAttr environment/henv
                                            SQL_ATTR_ODBC_VERSION
                                            SQL_OV_ODBC3
                                            0                                   ODBC_DEBUG ["SQLSetEnvAttr " result lf]
                                                                                if result = SQL_ERROR [
                                                                                    diagnose-error SQL_HANDLE_ENV environment/henv
                                                                                    return false
                                                                                ]
            return true
        ]


        ;---------------------------------------------------- open-connection --
        ;

        open-connection: func [
            datasource [red-string!]
            return:    [red-value!]
            /local
                connection result in-conn len1 [integer!] cstr [c-string!]
                out-conn sz2 len2 [integer!]
        ][
            ODBC_DEBUG ["OPEN-CONNECTION" lf]

            ;-- open environment?
            ;
            if environment/henv = null [
                open-environment
            ]

            ;-- Allocate a connection handle
            ;
            connection: as connection! allocate-buffer size? connection!

            result: result-of SQLAllocHandle SQL_HANDLE_DBC
                                             environment/henv
                                             as byte-ptr! :connection/hdbc      ODBC_DEBUG ["SQLAllocHandle " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_ENV environment/henv)]
            ;-- Connect to driver
            ;
            in-conn: unicode/to-utf16 datasource
            len1: string/rs-length? datasource

            sz2:  4096
            out-conn: make-c-string sz2
            len2: 0

            result: result-of SQLDriverConnect connection/hdbc
                                               null
                                               as byte-ptr! in-conn
                                               len1
                                               as byte-ptr! out-conn
                                               sz2
                                               :len2
                                               SQL_DRIVER_NOPROMPT              ODBC_DEBUG ["SQLDriverConnect " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_DBC connection/hdbc)]

            environment/conn-cnt: environment/conn-cnt + 1

            as red-value! handle/box as integer! connection
        ]


        ;----------------------------------------------------- open-statement --
        ;

        open-statement: function [
            holder      [red-handle!]
            return:     [red-value!]
            /local
                connection statement result
        ][
            ODBC_DEBUG ["OPEN-STATEMENT" lf]

            connection: as connection! holder/value
            statement:  as statement!  allocate-buffer size? statement!

            ;-- Allocate a statement handle
            ;
            result: result-of SQLAllocHandle SQL_HANDLE_STMT
                                             connection/hdbc
                                             as byte-ptr! :statement/hstmt      ODBC_DEBUG ["SQLAllocHandle " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_DBC connection/hdbc)]
            as red-value! handle/box as integer! statement
        ]


        ;-------------------------------------------------- prepare-statement --
        ;

        prepare-statement: func [
            holder      [red-handle!]
            sql         [red-block!]
            return:     [red-value!]
            /local
                statement len query text result
        ][
            ODBC_DEBUG ["PREPARE-STATEMENT" lf]

            statement: as statement! holder/value

            len:  -1
            query: block/rs-head sql
            text: unicode/to-utf8 as red-string! query :len

            result: result-of SQLPrepare statement/hstmt
                                         as byte-ptr! text
                                         len                                    ODBC_DEBUG ["SQLPrepare " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_STMT statement/hstmt)]
            as red-value! logic/box true
        ]


        ;------------------------------------------------------- list-sources --
        ;

        list-sources: func [
            sources     [red-block!]
            return:     [red-value!]
            /local
                direction result
                server-name server-name-length buffer1-length
                description description-length buffer2-length
        ][
            ODBC_DEBUG ["LIST-SOURCES" lf]

            ;-- open environment?
            ;
            if environment/henv = null [
                open-environment
            ]

            ;-- list sources
            ;
            direction:          declare sqlsmallint!
            server-name-length: declare sqlsmallint!
            buffer1-length:     declare sqlsmallint!
            description-length: declare sqlsmallint!
            buffer2-length:     declare sqlsmallint!

            server-name:        allocate 1024
            description:        allocate 4096

            SET_INT16(buffer1-length 1024)
            SET_INT16(buffer2-length 4096)

            SET_INT16(direction SQL_FETCH_FIRST)
            until [
                result: result-of SQLDataSources environment/henv
                                                 direction
                                                 server-name
                                                 buffer1-length
                                                 server-name-length
                                                 description
                                                 buffer2-length
                                                 description-length             ODBC_DEBUG ["SQLDataSources " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_ENV environment/henv)]

                string/load-in as c-string! server-name GET_INT16(server-name-length) sources UTF-16LE
                string/load-in as c-string! description GET_INT16(description-length) sources UTF-16LE

                SET_INT16(direction SQL_FETCH_NEXT)

                result = SQL_NO_DATA
           ]

            return as red-value! logic/box true
        ]


        ;------------------------------------------------------- list-drivers --
        ;

        list-drivers: func [
            drivers     [red-block!]
            return:     [red-value!]
            /local
                direction result
                description description-length buffer1-length
                attributes  attributes-length  buffer2-length
        ][
            ODBC_DEBUG ["LIST-DRIVERS" lf]

            ;-- open environment?
            ;
            if environment/henv = null [
                open-environment
            ]

            ;-- list drivers
            ;
            direction:          declare sqlsmallint!
            description-length: declare sqlsmallint!
            buffer1-length:     declare sqlsmallint!
            attributes-length:  declare sqlsmallint!
            buffer2-length:     declare sqlsmallint!

            description:        allocate 1024
            attributes:         allocate 4096

            SET_INT16(buffer1-length 1024)
            SET_INT16(buffer2-length 4096)

            SET_INT16(direction SQL_FETCH_FIRST)
            until [
                result: result-of SQLDrivers environment/henv
                                             direction
                                             description
                                             buffer1-length
                                             description-length
                                             attributes
                                             buffer2-length
                                             attributes-length                  ODBC_DEBUG ["SQLDrivers " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_ENV environment/henv)]

                string/load-in as c-string! description GET_INT16(description-length) drivers UTF-16LE
                string/load-in as c-string! attributes  GET_INT16( attributes-length) drivers UTF-16LE

                SET_INT16(direction SQL_FETCH_NEXT)

                result = SQL_NO_DATA
           ]

            return as red-value! logic/box true
        ]


        ;-------------------------------------------------- catalog-statement --
        ;

        _tables:        symbol/make "tables"
        _columns:       symbol/make "columns"
        _types:         symbol/make "types"

        catalog-statement: func [
            holder      [red-handle!]
            catalog     [red-block!]
            return:     [red-value!]
            /local
                connection statement entity word sym all-types length result
        ][
            ODBC_DEBUG ["CATALOG-STATEMENT" lf]

            statement:  as statement! holder/value
            entity:     block/rs-head catalog
            word:       as red-word! entity
            sym:        symbol/resolve word/symbol

            case [
                sym = _tables [
                    length: declare sqlsmallint!
                    SET_INT16(length 0)

                    result: result-of SQLTables statement/hstmt
                                                null length
                                                null length
                                                null length
                                                null length                     ODBC_DEBUG ["SQLTables " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_STMT statement/hstmt)]
                ]
                sym = _columns [
                    length: declare sqlsmallint!
                    SET_INT16(length 0)

                    result: result-of SQLColumns statement/hstmt
                                                 null length
                                                 null length
                                                 null length
                                                 null length                    ODBC_DEBUG ["SQLColumns " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_STMT statement/hstmt)]
                ]
                sym = _types [
                    all-types: declare sqlsmallint!
                    SET_INT16(all-types SQL_ALL_TYPES)

                    result: result-of SQLGetTypeInfo statement/hstmt
                                                     all-types                  ODBC_DEBUG ["SQLGetTypeInfo " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_STMT statement/hstmt)]
                ]
            ]

            return as red-value! logic/box true
        ]


        ;----------------------------------------------------- bind-parameter --
        ;

        bind-parameter: func [
            hstmt       [sql-handle!]
            param       [param!]
            num         [integer!]
            value       [red-value!]
            return:     [red-value!]
            /local
                count io-type c-type sql-type digits column-size buffer-size
                strlen-ind int-buffer bit-buffer red-str str-len bit result
        ][
            ODBC_DEBUG ["BIND-PARAMETER" lf]

            count:           declare sqlsmallint!
            io-type:         declare sqlsmallint!
            c-type:          declare sqlsmallint!
            sql-type:        declare sqlsmallint!
            digits:          declare sqlsmallint!

            SET_INT16(count         num)
            SET_INT16(io-type       SQL_PARAM_INPUT)
            SET_INT16(digits        0)
            column-size:            0
            strlen-ind:             0

            switch TYPE_OF(value) [
                TYPE_INTEGER [
                    SET_INT16(c-type    SQL_C_LONG)
                    SET_INT16(sql-type  SQL_INTEGER)
                    buffer-size:        4
                    param/buffer:       allocate-buffer buffer-size
                    int-buffer:         as pointer! [integer!] param/buffer
                    int-buffer/value:   integer/get as red-value! value
                ]
                TYPE_STRING [
                    SET_INT16(c-type    SQL_C_WCHAR)
                    SET_INT16(sql-type  SQL_VARCHAR)
                    red-str:            as red-string! value
                    str-len:            string/rs-length? red-str
                    buffer-size:        str-len + 1 << 1
                    param/buffer:       as byte-ptr! unicode/to-utf16 red-str
                    column-size:        SQL_NTS
                    strlen-ind:         SQL_NTS
                ]
                TYPE_LOGIC [
                    SET_INT16(c-type    SQL_C_BIT)
                    SET_INT16(sql-type  SQL_BIT)
                    bit:                logic/get as red-value! value
                    buffer-size:        1
                    param/buffer:       allocate-buffer buffer-size
                    bit-buffer:         param/buffer
                    bit-buffer/0:       either bit [#"^(00)"] [#"^(01)"]
                ]
                default [
                    SET_INT16(c-type    SQL_C_DEFAULT)
                    SET_INT16(sql-type  SQL_NULL_DATA)
                    buffer-size:        0
                    param/buffer:       null
                    strlen-ind:         SQL_NULL_DATA
                ]
            ]

            result: result-of SQLBindParameter hstmt
                                               count
                                               io-type
                                               c-type
                                               sql-type
                                               column-size
                                               digits
                                               param/buffer
                                               buffer-size
                                              :strlen-ind                       ODBC_DEBUG ["SQLBindParameter " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_STMT hstmt)]
            as red-value! logic/box true
        ]


        ;-------------------------------------------------- execute-statement --
        ;

        execute-statement: func [
            holder      [red-handle!]
            sql         [red-block!]
            return:     [red-value!]
            /local
                statement result value p param
        ][
            ODBC_DEBUG ["EXECUTE-STATEMENT" lf]

            statement:  as statement! holder/value

            unless statement/params = null [                                    ;-- first, free previously allocated params
                param: statement/params                                         ;   and their related buffers, if any
                loop statement/params-cnt [
                    unless param/buffer = null [
                        free-buffer param/buffer
                    ]
                    param: param + 1
                ]
                free-buffer as byte-ptr! statement/params
            ]

            statement/params-cnt: (block/rs-length? sql) - 1
            statement/params:      as param! allocate-buffer statement/params-cnt * size? byte-ptr!
                                                                                ;-- then, allocate new array of params

            value: (block/rs-head sql) + 1                                      ;-- skip statement string
            param: statement/params
            p:     1

            loop statement/params-cnt [
                bind-parameter statement/hstmt param p value

                value: value + 1
                param: param + 1
                p:     p     + 1
            ]

            result: result-of SQLExecute statement/hstmt                        ODBC_DEBUG ["SQLExecute " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_STMT statement/hstmt)]
            as red-value! logic/box true
        ]


        ;---------------------------------------------------- describe-column --
        ;

        describe-column: func [
            hstmt       [sql-handle!]
            column      [column!]
            num         [integer!]
            columns     [red-block!]
            return:     [red-value!]
            /local
                result count buffer-size name-length sql-type digits nullable
        ][
            ODBC_DEBUG ["DESCRIBE-COLUMN" lf]

            count:          declare sqlsmallint!
            buffer-size:    declare sqlsmallint!
            name-length:    declare sqlsmallint!
            sql-type:       declare sqlsmallint!
            digits:         declare sqlsmallint!
            nullable:       declare sqlsmallint!

            column/name:    as c-string! allocate-buffer 256

            SET_INT16(count num)
            SET_INT16(buffer-size 256)

            result: result-of SQLDescribeCol hstmt
                                             count
                                             column/name
                                             buffer-size
                                             name-length
                                             sql-type
                                            :column/column-size
                                             digits
                                             nullable                           ODBC_DEBUG ["SQLDescribeCol " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_STMT hstmt)]
            column/name-length: GET_INT16(name-length)
            column/sql-type:    GET_INT16(sql-type)
            column/digits:      GET_INT16(digits)
            column/nullable:    GET_INT16(nullable)

            string/load-in column/name column/name-length columns UTF-16LE

            as red-value! logic/box true
        ]


        ;-------------------------------------------------------- bind-column --
        ;

        bind-column: func [
            hstmt       [sql-handle!]
            column      [column!]
            num         [integer!]
            return:     [red-value!]
            /local
                result count
        ][
            ODBC_DEBUG ["BIND-COLUMN" lf]

            count:  declare sqlsmallint!

            switch column/sql-type [
                SQL_SMALLINT
                SQL_TINYINT
                SQL_INTEGER [
                    SET_INT16(column/c-type SQL_C_LONG)
                    column/buffer-size:     4
                ]
                ;SQL_NUMERIC [
                ;    SET_INT16(column/c-type SQL_C_LONG)
                ;    column/buffer-size:    4
                ;]
                ;SQL_DECIMAL []
                ;SQL_DATE SQL_TYPE_DATE [ ;-- Error 22007, Invalid datetime format 107
                ;    SET_INT16(column/c-type SQL_C_TYPE_DATE)
                ;    ODBC_DEBUG [size? SQL_DATE_STRUCT " " SQL_C_TYPE_DATE " " column/datatype ", "]
                ;    column/buffer-size:    size? SQL_DATE_STRUCT
                ;]
                SQL_DATE
                SQL_TYPE_DATE [
                    SET_INT16(column/c-type SQL_C_WCHAR)
                    column/buffer-size:     SQL_DATE_LEN + 1 << 22
                ]
                SQL_TYPE_TIME [
                    SET_INT16(column/c-type SQL_C_WCHAR)
                    column/buffer-size:     SQL_TIME_LEN + 1 << 1
                ]
                SQL_TYPE_TIMESTAMP [
                    SET_INT16(column/c-type SQL_C_WCHAR)
                    column/buffer-size:     SQL_TIMESTAMP_LEN + 1 << 1
                ]
                SQL_BIT [
                    SET_INT16(column/c-type SQL_C_CHAR)
                    column/buffer-size:     4                                   ;-- FIXE: hardcoded value
                ]
                SQL_CHAR
                SQL_WCHAR
                SQL_VARCHAR
                SQL_WVARCHAR [
                    column/c-type/lo:       as byte! SQL_C_WCHAR and FFh
                    column/c-type/hi:       as byte! SQL_C_WCHAR >> 8 and FFh
                    column/buffer-size:     (column/column-size + 1) << 1
                ]
                ;SQL_BINARY SQL_VARBINARY [
                ;]
                default [
                    column/buffer-size:     0                                   ;-- FIXME: hardcoded value
                    column/buffer:          null
                ]
            ]

            unless zero? column/buffer-size [
                column/buffer: allocate-buffer column/buffer-size
            ]

            SET_INT16(count num)

            result: result-of SQLBindCol hstmt
                                         count
                                         column/c-type
                                         column/buffer                      ;-- incl. null-termination
                                         column/buffer-size                 ;           -"-
                                        :column/strlen-ind                  ODBC_DEBUG ["SQLBindCol " result lf]
                                                                            if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_STMT hstmt)]
            as red-value! logic/box true
        ]


        ;------------------------------------------------- describe-statement --
        ;

        describe-statement: func [
            holder      [red-handle!]
            columns     [red-block!]
            return:     [red-value!]
            /local
                statement result count c column
        ][
            ODBC_DEBUG ["DESCRIBE-STATEMENT" lf]

            count:      declare sqlsmallint!
            
            statement:  as statement! holder/value

            result:     result-of SQLNumResultCols statement/hstmt
                                                   as byte-ptr! count           ODBC_DEBUG ["SQLNumResultCols " result lf]
                                                                                if result = SQL_ERROR [DESCRIBE_ERROR(SQL_HANDLE_STMT statement/hstmt)]
            statement/columns-cnt:  GET_INT16(count)
            statement/columns:      as column! allocate-buffer statement/columns-cnt * size? column!

            column: statement/columns
            c:      1

            loop statement/columns-cnt [
                describe-column statement/hstmt column c columns
                
                bind-column     statement/hstmt column c

                column: column + 1
                c:      c + 1
            ]
                
            as red-value! logic/box true
        ]


        ;------------------------------------------------------- fetch-column --
        ;

        fetch-column: func [
            hstmt       [sql-handle!]
            row         [red-block!]
            column      [column!]
            /local
                result buffer integer-ptr float-ptr date-ptr value
                year month day hour minute secs
        ][
            ODBC_DEBUG ["FETCH-COLUMN" lf]

            if column/strlen-ind = SQL_NULL_DATA [                              ;-- early exit with NONE value
                none/make-in row
                exit
            ]

            switch column/sql-type [
                SQL_SMALLINT
                SQL_TINYINT
                SQL_INTEGER [
                    integer-ptr: as [pointer! [integer!]] column/buffer
                    integer/make-in row integer-ptr/value
                ]
                ;SQL_NUMERIC [
                ;    integer-ptr: as [pointer! [integer!]] column/buffer
                ;    float/make-in row integer-ptr/value 0
                ;]
                ;SQL_DATE
                ;SQL_TYPE_DATE [
                ;    date-ptr: as SQL_DATE_STRUCT column/buffer
                ;    year:   (as integer! date-ptr/year_hi ) << 4 or (as integer! date-ptr/year_lo)
                ;    month:  (as integer! date-ptr/month_hi) << 4 or (as integer! date-ptr/month_lo)
                ;    day:    (as integer! date-ptr/day_hi  ) << 4 or (as integer! date-ptr/day_lo)
                ;
                ;    integer/make-in row year
                ;]
                SQL_DATE
                SQL_TYPE_DATE [
                    value: as c-string! column/buffer
                    string/load-in as c-string! column/buffer 10 row UTF-16LE
                ]
                SQL_TYPE_TIME [
                    value: as c-string! column/buffer
                    string/load-in as c-string! column/buffer 8 row UTF-16LE
                ]
                SQL_TYPE_TIMESTAMP [
                    value: as c-string! column/buffer
                    string/load-in as c-string! column/buffer 19 row UTF-16LE
                ]
                SQL_BIT [
                    logic/make-in row all [column/buffer/0 = #"^(8C)" column/buffer/1 = #"^(31)"]
                ]
                SQL_CHAR
                SQL_VARCHAR [
                    value: as c-string! column/buffer
                    string/load-in as c-string! column/buffer column/strlen-ind >> 1 row UTF-16LE
                ]
                default [
                    integer/make-in row 0
                ]
            ]
        ]


        ;---------------------------------------------------- fetch-statement --
        ;

        fetch-statement: func [
            holder      [red-handle!]
            rows        [red-block!]
            return:     [red-value!]
            /local
                statement result c row column buffer datatype option
                integer-ptr float-ptr date-ptr year month day buf
        ][
            ODBC_DEBUG ["FETCH-STATEMENT" lf]

            option:    declare sqlsmallint!
            statement: as statement! holder/value

            until [
                result: result-of SQLFetch statement/hstmt                      ODBC_DEBUG ["SQLFetch " result lf]

                switch result [
                    SQL_SUCCESS
                    SQL_SUCCESS_WITH_INFO [
                        row: block/make-in rows statement/columns-cnt

                        column: statement/columns
                        c: 1

                        loop statement/columns-cnt [
                            fetch-column statement/hstmt row column

                            column: column + 1
                            c: c + 1
                        ]
                    ]
                    SQL_ERROR
                    SQL_INVALID_HANDLE
                    SQL_STILL_EXECUTING [                                       DESCRIBE_ERROR(SQL_HANDLE_STMT statement/hstmt)
                    ]
                    SQL_NO_DATA [
                        ;-- no-op
                    ]
                ]

                result = SQL_NO_DATA
            ]

            result: result-of SQLCloseCursor statement/hstmt                    ODBC_DEBUG ["SQLCloseCursor " result lf]
                                                                                if any [result = SQL_ERROR
                                                                                        result = SQL_INVALID_HANDLE] [DESCRIBE_ERROR(SQL_HANDLE_STMT statement/hstmt)]
            SET_INT16(option SQL_CLOSE)
            result: result-of SQLFreeStmt statement/hstmt option                ODBC_DEBUG ["SQLFreeStmt SQL_CLOSE " result lf]

            SET_INT16(option SQL_UNBIND)
            result: result-of SQLFreeStmt statement/hstmt option                ODBC_DEBUG ["SQLFreeStmt SQL_UNBIND " result lf]

            SET_INT16(option SQL_RESET_PARAMS)
            result: result-of SQLFreeStmt statement/hstmt option                ODBC_DEBUG ["SQLFreeStmt SQL_RESET_PARAMS " result lf]

            as red-value! logic/box true
        ]


        ;---------------------------------------------------- close-statement --
        ;

        close-statement: func [
            holder    [red-handle!]
            return:   [red-value!]
            /local
                statement result column
        ][
                                                                                ODBC_DEBUG ["CLOSE-STATEMENT" lf]
            statement:  as statement! holder/value
            column:     statement/columns

            loop statement/columns-cnt [
                free-buffer column/buffer
                column: column + 1
            ]

            free-buffer as byte-ptr! statement/columns

            result: result-of SQLFreeHandle SQL_HANDLE_STMT statement/hstmt     ODBC_DEBUG ["SQLFreeHandle " result lf]
                                                                                if any [result = SQL_ERROR
                                                                                        result = SQL_INVALID_HANDLE] [DESCRIBE_ERROR(SQL_HANDLE_STMT statement/hstmt)]
            free-buffer as byte-ptr!  statement
            as red-value! logic/box true
        ]


        ;--------------------------------------------------- close-connection --
        ;

        close-connection: func [
            holder      [red-handle!]
            return:     [red-value!]
            /local
                connection result
        ][
                                                                                ODBC_DEBUG ["CLOSE-CONNECTION" lf]
            connection: as connection! holder/value
            result: result-of SQLDisconnect connection/hdbc                     ODBC_DEBUG ["SQLDisconnect " result lf]
                                                                                if any [result = SQL_ERROR
                                                                                        result = SQL_INVALID_HANDLE
                                                                                        result = SQL_STILL_EXECUTING] [DESCRIBE_ERROR(SQL_HANDLE_DBC connection/hdbc)]

            result: result-of SQLFreeHandle SQL_HANDLE_DBC connection/hdbc      ODBC_DEBUG ["SQLFreeHandle " result lf]
                                                                                if any [result = SQL_ERROR
                                                                                        result = SQL_INVALID_HANDLE] [DESCRIBE_ERROR(SQL_HANDLE_DBC connection/hdbc)]
            free-buffer as byte-ptr! connection

            environment/conn-cnt: environment/conn-cnt - 1

            if zero? environment/conn-cnt [close-environment]

            as red-value! logic/box true
        ]


        ;-------------------------------------------------- close-environment --
        ;

        close-environment: func [
            return:     [red-value!]
            /local
                result
        ][
            result: result-of SQLFreeHandle SQL_HANDLE_ENV environment/henv     ODBC_DEBUG ["SQLFreeHandle " result lf]
                                                                                if any [result = SQL_ERROR
                                                                                        result = SQL_INVALID_HANDLE] [DESCRIBE_ERROR(SQL_HANDLE_ENV environment/henv)]

            as red-value! logic/box true
        ]


        ;----------------------------------------------------- diagnose-error --
        ;

        diagnose-error: func [
            type    [integer!]
            holder  [sql-handle!]
            /local
                result state native-error message-text text-length buffer-length
                message char record
        ][
            record: 0
            until [
                record: record + 1

                state:        as c-string! allocate-buffer 12
                native-error: 0
                text-length:  0

                result: SQLGetDiagRec type
                                      holder
                                      record
                                      as byte-ptr! state
                                     :native-error
                                      null
                                      0
                                     :text-length                               ODBC_DEBUG ["SQLGetDiagRecord " result lf]
                                                                                unless result = SQL_SUCCESS [exit]
                buffer-length: (text-length + 1) << 1
                message:        as c-string! allocate-buffer buffer-length

                result: SQLGetDiagRec type
                                      holder
                                      record
                                      as byte-ptr! state
                                     :native-error
                                      as byte-ptr! message
                                      buffer-length
                                     :text-length                               print ["SQLGetDiagRecord " result " " state " " native-error " " message " " text-length lf]
                                                                                unless result = SQL_SUCCESS [exit]
                result = SQL_NO_DATA
            ]
        ]


        ;-------------------------------------------------------- throw-error --
        ;

        throw-error: func [
            cmds            [red-block!]
            cmd             [red-value!]
            catch?          [logic!]
            /local
                base        [red-value!]
        ][
            base:       block/rs-head cmds
            cmds:       as red-block! stack/push as red-value! cmds
            cmds/head: (as-integer cmd - base) >> 4

            fire [TO_ERROR(script invalid-data) cmds]
        ]
    ]
]


;======================================================================== Red ==
;

context [

    ;--------------------------------------------------------------- routines --
    ;

    _list-sources:       routine [sources [block!]] [odbc/list-sources sources]
    _list-drivers:       routine [drivers [block!]] [odbc/list-drivers drivers]

    _open-connection:    routine [dsn [string!]] [odbc/open-connection dsn]

    _open-statement:     routine [connection [handle!]] [odbc/open-statement  connection]
    _prepare-statement:  routine [statement  [handle!] sql     [block!]] [odbc/prepare-statement  statement sql    ]
    _execute-statement:  routine [statement  [handle!] sql     [block!]] [odbc/execute-statement  statement sql    ]
    _describe-statement: routine [statement  [handle!] columns [block!]] [odbc/describe-statement statement columns]
    _fetch-statement:    routine [statement  [handle!] rows    [block!]] [odbc/fetch-statement    statement rows   ]
    _catalog-statement:  routine [statement  [handle!] catalog [block!]] [odbc/catalog-statement  statement catalog]

    _close-statement:    routine [statement  [handle!]] [odbc/close-statement  statement ]
    _close-connection:   routine [connection [handle!]] [odbc/close-connection connection]


    ;----------------------------------------------------------------- protos --
    ;

    connection-proto: object [
        type:      'connection
        handle:     none
        statements: []
    ]

    statement-proto: object [
        type:      'statement
        handle:     none
        connection: none
        sql:        none
    ]


    ;------------------------------------------------------------------- open --
    ;

    set 'odbc-open function [
        "Connect to a datasource."
        datasource [string!] "connection string"
    ][
        any [handle: _open-connection datasource                                cause-error 'user 'message ["Error opening connection."]]

        make connection-proto compose [
            handle: (handle)
        ]
    ]


    ;------------------------------------------------------------------ first --
    ;

    set 'odbc-first function [
        "Returns an ODBC statement."
        connection [object!]
    ][
        any [handle: _open-statement connection/handle                          cause-error 'user 'message ["Error opening statement."]]

        statement: make statement-proto compose [
            handle:     (handle)
            connection: (connection)
            sql:         none
        ]

        append connection/statements statement

        statement
    ]


    ;---------------------------------------------------------------- sources --
    ;

    set 'odbc-sources function [
        "Returns block of ODBC datasource/description pairs"
    ][
        any [_list-sources sources: copy []                                     cause-error 'user 'message ["Error fetching datasources."]]

        new-line/skip/all sources on 2
    ]


    ;---------------------------------------------------------------- drivers --
    ;

    set 'odbc-drivers function [
        "Returns block of ODBC driver-description/attributes pairs"
        /local desc attrs attr
    ][
        any [_list-drivers drivers: copy []                                     cause-error 'user 'message ["Error fetching drivers."]]

        drivers: collect [foreach [desc attrs] drivers [
            attrs: split head remove back tail attrs #"^@"
            attrs: collect [foreach attr attrs [
                pair: split attr #"="
                keep to word! first pair
                keep second pair
            ]]

            keep reduce [desc attrs]
        ]]

        new-line/skip/all drivers on 2
    ]


    ;----------------------------------------------------------------- insert --
    ;

    set 'odbc-insert function [
        "Executes SQL statement."
        statement [object!]
        sql [string! word! block!] "statement w/o parameter(s) (block gets reduced) or TABLES, COLUMNS or TYPES catalog"
        /local
            column
    ][
        query: reduce either block? sql [sql] [[sql]]                           ;-- block argument

        any [parse query [[string! | 'tables | 'columns | 'types] to end]       cause-error 'script 'invalid-arg [sql]]

        switch type?/word value: first query [
            word! [ ;-- catalog --
                any [ _catalog-statement statement/handle query                 cause-error 'access 'cannot-open [sql]]
                any [_describe-statement statement/handle result: copy []       cause-error 'access 'cannot-open [sql]]
            ]

            string! [ ;-- statement --
                unless same? statement/sql value [                              ;-- prepare new statement
                    any [_prepare-statement statement/handle query              cause-error 'access 'cannot-open [sql]]
                    statement/sql: value
                ]

                any [ _execute-statement statement/handle query                 cause-error 'access 'cannot-open [sql]]
                any [_describe-statement statement/handle result: copy []       cause-error 'access 'cannot-open [sql]]
            ]
        ]

        either integer? rows: first result [
            rows                                                                ;-- number of affected rows
        ][
            collect [foreach column result [keep to word! column]]              ;-- column titles
        ]
    ]


    ;------------------------------------------------------------------- copy --
    ;

    set 'odbc-copy function [
        "Copy data from executed SQL statement."
        statement [object!]
    ][
		any [_fetch-statement statement/handle rows: copy []                 cause-error 'user 'message ["Error fetch statement."]]

        new-line/all rows on
    ]


    ;------------------------------------------------------------------ close --
    ;

    set 'odbc-close function [
        "Close connection or statement."
        entity [object!] "connection or statement handle"
    ][
        any [in entity 'type                                                    cause-error 'script 'invalid-arg [entity]]

        switch entity/type [
            connection [
                while [not tail? entity/statements] [
                    odbc-close take entity/statements
                ]

                _close-connection entity/handle
                entity/statements: copy []
            ]
            statement [
                _close-statement entity/handle
                entity/connection: none
            ]
        ]

        entity/handle: none
        entity
    ]

]

