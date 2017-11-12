let

// ## three functions to prepare the following lists:
//  list of speakers
//  list of original file URL (external source - due to the firewall error)
//  list of file names that are cleaned up for the matching

    // ## function - get list of speakers
    get_all_speakers = (event_table) =>
    let
        // ## get all speakers' name
        max_num_speakers = 8,
        list_speakers_columns = List.Transform({1..max_num_speakers}, each "Speaker " & Number.ToText(_)),

        get_column_contents = (col_name) =>
        let
            column = Table.Column(event_table, col_name),
            remove_nulls = List.RemoveNulls(column)
        in
            remove_nulls,

        // ## iterate through the speaker columns to gather all the speakers' names
        iterate_columns =    
            List.Generate(
                () => [ i = 1, ln = {} ], 
                each [i] < List.Count(list_speakers_columns), 
                each [ 
                    i = List.Count([ln]), 
                    ln = [ln] & get_column_contents(list_speakers_columns{i})
                ], 
                each [ln]
            ),

        // ## remove any duplicates and sort names in ascending order
        return = List.Sort(List.Distinct(List.Last(iterate_columns)))
    in
        return,

    // ## function - get file names (cleaned up for matching)
    get_clean_file_names = (files) =>
    let
        str_delimiter = "|",
        fn_get_file_name = (url) =>
        let
            // ## remove file path and extension from URL
            //  apply proper format (capitalize each word)
            file_name = List.Last(Text.Split(url, "/")),
            remove_extension = Text.Start(file_name, Text.PositionOf(file_name, ".", Occurrence.Last)),
            format_proper = Text.Proper(remove_extension)
        in
            format_proper,

        get_file_name = List.Transform(files, each fn_get_file_name(_)),
        
        fn_remove_non_alpha_chrs = (txt) =>
        let
            str_non_alpha_chrs = "-|.|_",
            selected = List.Select(Text.Split(str_non_alpha_chrs, str_delimiter), each Text.Contains(txt, _)),
            get_chr_pos = List.Transform(selected, each Text.PositionOf(txt, _, Occurrence.All)),
            combine_and_sort = List.Sort(List.Combine(get_chr_pos)),
            
            // ## iterate through the list of non alpha chars and remove them from the original text string
            return =
                if List.Count(combine_and_sort) = 0 then
                    {txt}
                else 
                    List.Generate(
                        () => [ i = 0, ln = {}, t = txt ], 
                        each [i] < List.Count(combine_and_sort), 
                        each [ 
                            i = List.Count([ln]), 
                                ln = [ln] & {Text.ReplaceRange([t], combine_and_sort{i}, 1, " ")},
                                    t = Text.ReplaceRange([t], combine_and_sort{i}, 1, " ")
                        ], 
                        each [t]	
                    )        
        in    
            List.Last(return),
        remove_non_alpha_chrs = List.Transform(get_file_name, each fn_remove_non_alpha_chrs(_))
    in
        remove_non_alpha_chrs,

    // ## the main procedure starts here
    //  first off, assign the event table as a source

    source_data = Get_Event_Table,

    // ## using the functions above to assign the lists accordingly
    speakers_list = get_all_speakers(source_data),
    original_source = Image_File_URL,
    image_source_list = get_clean_file_names(original_source),   

    // ## function: find image URL by matching speaker name
    fn_find_image_source = (name) =>
    let

        first_name = Text.Split(name, " "){0},
        last_name = if 
            // ## in case there is a middle name
            List.Count(Text.Split(name, " ")) = 3 then 
                Text.Split(name, " "){2}
            else
                Text.Split(name, " "){1},

        fn_search_text = (txt, l_src) =>
        let
            // ## match regardless of case (both set to upper case)
            return_found = List.Select(l_src, each Text.Contains(Text.Upper(_), Text.Upper(txt)))
        in
            return_found,
        
        // ## check full name first
        //    then first and last name only
        //    last and first (inverse order)
        //    lastly, combined without space in between (firstlast)

        return_full_name = fn_search_text(name, image_source_list),
        return_first_last = if List.Count(return_full_name) = 0 then
            fn_search_text(first_name & " " & last_name, image_source_list) & return_full_name
            else
            return_full_name,
        return_last_first = if List.Count(return_first_last) = 0 then
            fn_search_text(last_name & " " & first_name, image_source_list) & return_first_last
            else
            return_first_last,
        return_combined = if List.Count(return_last_first) = 0 then
            fn_search_text(first_name & last_name, image_source_list) & return_last_first
            else
            return_last_first,
        
        // ## this will return all the combinations
        //list_zipped = List.Zip({List.Repeat({name}, List.Count(return_combined)), return_combined})
        
        // ## but only want to find the first in the matching items for this time
        list_zipped = List.PositionOf(image_source_list, List.First(return_combined))              
                
    in
        list_zipped,

    find_image_source = List.Transform(speakers_list, each List.Zip({{_}, {fn_find_image_source(_)}})),
    combine_list = List.Combine(find_image_source),
    convert_to_table = #table(type table [Name = text, #"Image Source" = number], combine_list),
    get_image_source_url = Table.TransformColumns(convert_to_table, {{"Image Source", each if _ > 0 then original_source{_} else null}}),
    change_column_type = Table.TransformColumnTypes(get_image_source_url, {"Image Source", type text})
in
    change_column_type