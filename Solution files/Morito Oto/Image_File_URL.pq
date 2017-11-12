// ## List all image file URL

let
    root_directory = "http://tdswe.se/wp-content/uploads/sites/11/2017/",
    list_system_items = {"Name", "Parent Directory"},    

    // ## function - get sub-directories
    get_sub_directory = (item) =>
    let 
        get_sub_url = List.RemoveItems(Web.Page(Web.Contents(item)){0}[Data][Name], list_system_items),
        return = List.Transform(get_sub_url, each Text.Combine({item, _}, ""))    
    in
        return,

    // list all sub-directories under the root
    list_full_directories = get_sub_directory(root_directory),
    get_full_items = List.Transform(list_full_directories, each get_sub_directory(_)),
    
    // combine all into a list
    turn_into_list = List.Union(get_full_items)
in
    turn_into_list