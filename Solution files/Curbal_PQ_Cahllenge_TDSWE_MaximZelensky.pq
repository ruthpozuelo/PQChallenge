let
    Source = Binary.Buffer(Web.Contents("http://tdswe.se/sessioner/")),
    // we need link, so we do not need Web.Page, do we?
    ToText = Text.FromBinary(Source), 
    // cut necessary info
    CutText = Text.BetweenDelimiters(ToText, "<div class=""col-xs-12 col-md-6"" data-lightweb-filter-result ", "<h4 class=""lightweb-filter-no-results"),
    
    // split events by event block mark
    SplitEvents = Text.Split(CutText, "<div class=""col-xs-12 col-md-6"" data-lightweb-filter-result "),
    ToTable = Table.FromList(SplitEvents, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    AddedIndex = Table.AddIndexColumn(ToTable, "Index", 1, 1),

    // Main parsing function
    GetOneEvent = 
        (OneEvent as text) as record =>
        let
        //    OneEvent = GetEvents{5}[Column1],
            CleanTabs = Text.Replace(OneEvent, "#(tab)",""),
            Cleaned = Text.Replace(CleanTabs, "#(lf)",""),

            // Collect data
            Link = Text.BetweenDelimiters(Cleaned, "<a class=""event-box-link"" href=""", """>"),
            Name = Text.BetweenDelimiters(Cleaned, "<h4 class=""mb-lg"">", "</h4>"),
            Place = Text.BetweenDelimiters(Cleaned, "<i class=""fa fa-map-marker"" aria-hidden=""true""></i> ", "</p>"),
            Description = Text.BetweenDelimiters(Cleaned, "</p></div></div><p>", "</p>"),

            // Collect Date and Time
            EventDate1 = Text.BetweenDelimiters(Cleaned, "<i class=""fa fa-calendar"" aria-hidden=""true""></i> ", "</p>"),
            Custom1 = Text.Split(EventDate1," "),
            Date = Date.From(Custom1{0},"sv-SE"),
            Start = Time.From(Custom1{1}?),
            Finish = Time.From(Text.BetweenDelimiters(Cleaned, "<p>– ", "</p>")),

            // Speakers
            // split speakers
            Sp1 = Text.Split(Cleaned, "<div class=""clearfix"">"), 
            Sp2 = List.Skip(Sp1,1),
                // get speakers info
            SpeakersList = List.Transform(Sp2, each 
                let
                    splitted = Splitter.SplitTextByEachDelimiter({"a href=""", """ class", "src=""", """ />", "<p>", "</p>"})(_),
                    // only necessary data
                    Alternate = List.Alternate(splitted,1,1,0)
                in
                    Record.ToTable(Record.FromList(Alternate, {"Link","Photo","Name"}))), 

            toTable = Table.FromList(SpeakersList, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
            // speakers numbering
            AddedIndex = Table.AddIndexColumn(toTable, "Index", 1, 1),
            AddedCustom = Table.AddColumn(AddedIndex, "Custom", each "Speaker" & Text.From([Index])),
            RemovedColumns = Table.RemoveColumns(AddedCustom,{"Index"}),
            Expanded = Table.ExpandTableColumn(RemovedColumns, "Column1", {"Name", "Value"}, {"Name", "Value"}),
            AddedCustom1 = Table.AddColumn(Expanded, "Cols", each [Custom]&"."&[Name]),
            // get one row (record) for all speakers
            Speakers = #table(AddedCustom1[Cols],{AddedCustom1[Value]}){0},

            // Result: collect all data in one record
            Collect = [Link = Link, Name = Name, Place = Place, Description = Description, Date = Date, Start = Start, Finish = Finish] & Speakers
        in
            Collect,
    // invoke parsing function
    GetEventData = Table.AddColumn(AddedIndex, "GetOneEvent", each GetOneEvent([Column1])),
    RemovedColumns = Table.RemoveColumns(GetEventData,{"Column1"}),
    // expand and format
        // dynamically collect all field names form event records (for unknown number of speakers)
    FieldsList = List.Union(List.Transform(RemovedColumns[GetOneEvent], each Record.FieldNames(_))),
        // expand all fields
    ExpandEventData = Table.ExpandRecordColumn(RemovedColumns, "GetOneEvent", FieldsList, FieldsList),
        // all to text - who knows, how much speakers there, so we do not hardcode fields list. But this step could be skipped
    ChangedType = Table.TransformColumnTypes(ExpandEventData, List.Transform(FieldsList, each {_, type text})),
        // format date-time columns
    ChangedType1 = Table.TransformColumnTypes(ChangedType,{{"Date", type date}, {"Start", type time}, {"Finish", type time}})
in
    ChangedType1