let

    // ## Transforming the given data saved in the worksheet to the event table (techday)
    //    Created by Morito Ota
    //    Date Last modified: 2017-10-22
    //    *Possible issue(s)
    //     - Works only for the specific set of data: Query is built for the specific format of the data
    //       Not flexible to adapt to the changes of how the data are formatted. Slight change would likely cause errors in query.
    

    // ## initial setup
    //    select the file directory, file name below.

    file_directory = "C:\Users\mota\Desktop",
    file_name = "Talare2 - (copied 2017-10-20).xlsx",

    file_contents = File.Contents(Text.Combine({file_directory, file_name}, "\")),
    source_workbook = Excel.Workbook(file_contents, null, true),
    sheet_name = "Data Source",

    get_sheet = (wrkbk, sh) =>
    let
        return = wrkbk{[Item = sh, Kind = "Sheet"]}
    in 
        return,

    // ## get the source data from worksheet
    source_worksheet = get_sheet(source_workbook, sheet_name)[Data],

    // ## clean up the data
    //  remove nulls
    //  remove date (unnecessary for this operation)
    //  remove lines for the contact info at the bottom (unecessary for this operation)
    str_other_info_header = "Övrig", // means others in swedish

    remove_nulls = List.RemoveNulls(source_worksheet[Column1]),
    remove_dates = List.Select(remove_nulls, each Value.Is(_, type date) = false),
    remove_contact_info = List.RemoveLastN(remove_dates, List.Count(remove_dates) - List.PositionOf(remove_dates, str_other_info_header)),


    // ## start converting the original sheet data to the table
    source_data = List.Transform(remove_contact_info, each Text.Trim(_)),
    convert_to_table = #table(type table [Column1 = text], List.Transform(source_data, each {_})),
    
    // ## custom filter = find out the rows that contains the date
    // this seems the only way to figure out the way to separate the rows by event
    //    structure:
    //        Session Title
    //        Date Start Time
    //        - End Time
    //        Room
    //        Description
    //        List of speakers (# of speakers ranging from 1 to 8)

    add_custom_filter_column = Table.AddColumn(
        convert_to_table, 
        "is_date", 
        each 
            // ## logic to identify if the [Column1] has date format [YYYY-MM-DD HH:MM]
            //    1) must have space in text string
            //    then,
            //        2) length of text string prior to the space matches the length of 'YYYY-MM-DD' (10)
            //        3) also contains hyphens (-)
            //        4) lastly, it is a date            
            if Text.PositionOf([Column1], " ") > 0 then
                if 
                    Text.Length(Text.Start([Column1], Text.PositionOf([Column1], " "))) = Text.Length("YYYY-MM-DD") and 
                    Text.Contains(Text.Start([Column1], Text.PositionOf([Column1], " ")), "-") then
                        Value.Is(Date.FromText(Text.Start([Column1], Text.PositionOf([Column1], " "))), type date)
                else 
                    false
            else 
                false, 
        type logical
    ),

    // ## figuring out the grouping technique 
    //     add index
    //     add another customer filter to pick the index when the first custom filter (is_date) = true
    //     then, fill down the custom filter column
    //     lastly, create the third custom filter column for the grouping index

    add_index_column = Table.AddIndexColumn(add_custom_filter_column, "Index", 1, 1),
    add_custom_filter_column_2 = Table.AddColumn(add_index_column, "Custom", each if [is_date] then [Index] else null, type number),
    fill_down_custom_filter_column_2 = Table.FillDown(add_custom_filter_column_2, {"Custom"}),
    

    add_custom_filter_column_3 = Table.AddColumn(
        fill_down_custom_filter_column_2, 
        "Custom.1", 
        each 
            // ## handling the exception for the last row (Index > List.Count - 1)
            //    otherwise get custom column
            //    this enables to shift up the values in custom
            //        {null, 0,1,2} => {0,1,2,2}    
            if [Index] > List.Count(Table.Column(fill_down_custom_filter_column_2, "Custom")) - 1 then 
                [Custom] 
            else
                Table.Column(fill_down_custom_filter_column_2, "Custom"){[Index]}
        , type number
    ),

    remove_custom_filter_columns = Table.RemoveColumns(add_custom_filter_column_3, {"is_date", "Index", "Custom"}),
    group_rows_by_custom_filter_2 = Table.Group(remove_custom_filter_columns, {"Custom.1"}, {{"Count", each Table.Column(_, "Column1"), type list}}),

    str_delimiter = "|",

    combine_grouped_rows_into_columns = Table.TransformColumns(
        group_rows_by_custom_filter_2, 
        {
            "Count", 
            each Text.Combine(List.Transform(_, Text.From), str_delimiter), 
            type text
        }
    ),

    // ## finding out the number of columns (varies depending on maximum # of speakers)
    find_num_of_cols = List.Transform(
            Table.Column(combine_grouped_rows_into_columns, "Count"), 
            each List.Count(Text.Split(_, str_delimiter))
    ),
    find_max_cols = List.Max(find_num_of_cols),

    // ## generate generic column headers (Column 1, Column 2, ...Column n)
    generate_col_header = List.Transform({1..Number.From(find_max_cols)}, each "Column " & Number.ToText(_)),

    // ## expand the data into columns by spliting the text by delimiter
    split_into_columns = Table.SplitColumn(
        combine_grouped_rows_into_columns, 
        "Count", 
        Splitter.SplitTextByDelimiter(str_delimiter, QuoteStyle.Csv), 
        generate_col_header),
    remove_group_num_column = Table.RemoveColumns(split_into_columns, {"Custom.1"}),


    // ## combine columns
    combine_columns = Table.CombineColumns(
            remove_group_num_column, 
            {"Column 2", "Column 3"},
            Combiner.CombineTextByDelimiter(str_delimiter), 
            "Merged"
    ),
    
    // ## function to split into columns (event date and start time, event date, start time, end time)
    group_date_columns = (row) =>
    let 
        split_by_delimiter = Text.Split(row, str_delimiter),

        // ## { event date ' ' time, - end time }
        //    part 1: get event date and time
        split_text_1 = Text.Split(split_by_delimiter{0}, " "),
        event_date = Date.FromText(split_text_1{0}),
        start_time = Time.FromText(split_text_1{1}),

        // ## part 2: remove hyphen and get end time
        remove_hyphen_split_text_2 = Text.Remove(split_by_delimiter{1}, "–"),
        trimmed_split_text_2 = Text.Trim(remove_hyphen_split_text_2),
        end_time = Time.FromText(trimmed_split_text_2),
    
        // ## combine into list        
        list_items = {
            event_date & start_time,
            event_date,
            start_time,
            end_time
        },
        
        // ## convert list into table
        return_table = #table(
            type table [
                #"Start Date/Time" = datetime, 
                #"Date" = date, 
                Start = time, 
                End = time
            ], 
            {list_items}
        ) 

    in
        return_table,

    // ## group dates columns into one and turn into a table contains four columns (Event date and time, date, start, end)
    return_group_date_columns = Table.TransformColumns(combine_columns, {"Merged", each group_date_columns(_)}),

    // ## create the list of new column headers
    basic_column_header = {
        "Session Title",
        "Event date and time",
        "Room",
        "Description"
    },
    speaker_columns = List.Transform({1..8}, each "Speaker " & Number.ToText(_)),
    new_column_header = List.Combine({basic_column_header, speaker_columns}),

    // ## change the column headers
    change_column_header = Table.RenameColumns(return_group_date_columns, List.Zip({Table.ColumnNames(return_group_date_columns), new_column_header}), MissingField.Ignore),

    // ## expand the date table into columns
    list_dates_column_name = {"Start Date/Time", "Date", "Start", "End"},
    expand_date_columns = Table.ExpandTableColumn(change_column_header, "Event date and time", list_dates_column_name, list_dates_column_name),

    // ## final touch : change column type and reorder columns
    change_column_type = Table.TransformColumnTypes(expand_date_columns, {{"Start Date/Time", type datetime}, {"Date", type datetime}, {"Start", type time}, {"End", type time}}),
    reorder_columns = Table.ReorderColumns(change_column_type, {"Start Date/Time", "Date", "Start", "End", "Room", "Session Title", "Description"}, MissingField.Ignore)

in
    reorder_columns