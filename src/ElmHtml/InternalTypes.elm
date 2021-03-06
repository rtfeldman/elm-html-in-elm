module ElmHtml.InternalTypes
    exposing
        ( ElmHtml(..)
        , TextTagRecord
        , NodeRecord
        , CustomNodeRecord
        , MarkdownNodeRecord
        , Facts
        , decodeElmHtml
        , emptyFacts
        )

{-| Internal types used to represent Elm Html

@docs ElmHtml, TextTagRecord, NodeRecord, CustomNodeRecord, MarkdownNodeRecord, Facts
@docs decodeElmHtml, emptyFacts
-}

import Dict exposing (Dict)
import Json.Encode
import Json.Decode exposing (field)
import ElmHtml.Markdown exposing (..)
import ElmHtml.Constants exposing (..)
import ElmHtml.Helpers exposing (..)


{-| Type tree for representing Elm's Html
- TextTag is just a plain old bit of text.
- NodeEntry is an actual HTML node, e.g a div
- CustomNode are nodes defined to work with the renderer in some way, e.g webgl/markdown
- MarkdownNode is just a wrapper for CustomNode designed just for markdown
-}
type ElmHtml
    = TextTag TextTagRecord
    | NodeEntry NodeRecord
    | CustomNode CustomNodeRecord
    | MarkdownNode MarkdownNodeRecord
    | NoOp


{-| Text tags just contain text
-}
type alias TextTagRecord =
    { text : String }


{-| A node contains the `tag` as a string, the children, the facts (e.g attributes) and descendantsCount
-}
type alias NodeRecord =
    { tag : String
    , children : List ElmHtml
    , facts :
        Facts
        --, namespace : String
    , descendantsCount : Int
    }


{-| A markdown node contains facts (e.g attributes) and the model used by markdown
-}
type alias MarkdownNodeRecord =
    { facts : Facts
    , model : MarkdownModel
    }


{-| Custom nodes contain facts (e.g attributes) and a json value for the model
-}
type alias CustomNodeRecord =
    { facts : Facts
    , model : Json.Decode.Value
    }


{-| Facts contain various dictionaries and values for a node
- styles are a mapping of rules
- events may be a json object containing event handlers
- attributes are pulled out into stringAttributes and boolAttributes - things with string values go into
  stringAttributes, things with bool values go into boolAttributes
-}
type alias Facts =
    { styles : Dict String String
    , events : Maybe Json.Decode.Value
    , attributes : Maybe Json.Decode.Value
    , attributeNamespace : Maybe Json.Decode.Value
    , stringAttributes : Dict String String
    , boolAttributes : Dict String Bool
    }


{-| decode a json object into ElmHtml
-}
decodeElmHtml : Json.Decode.Decoder ElmHtml
decodeElmHtml =
    field "type" Json.Decode.string
        |> Json.Decode.andThen
            (\typeString ->
                case typeString of
                    "text" ->
                        Json.Decode.map TextTag (decodeTextTag)

                    "node" ->
                        Json.Decode.map NodeEntry (decodeNode)

                    "custom" ->
                        decodeCustomNode

                    "tagger" ->
                        decodeTagger

                    _ ->
                        Json.Decode.fail ("No such type as " ++ typeString)
            )


{-| decode text tag
-}
decodeTextTag : Json.Decode.Decoder TextTagRecord
decodeTextTag =
    field "text" (Json.Decode.andThen (\text -> Json.Decode.succeed { text = text }) Json.Decode.string)


{-| encode text tag
-}
encodeTextTag : TextTagRecord -> Json.Encode.Value
encodeTextTag { text } =
    Json.Encode.object [ ( "text", Json.Encode.string text ) ]


{-| decode a tagger
-}
decodeTagger : Json.Decode.Decoder ElmHtml
decodeTagger =
    Json.Decode.oneOf
        [ Json.Decode.at [ "node" ] decodeElmHtml
        , Json.Decode.at [ "text" ] decodeElmHtml
        , Json.Decode.at [ "custom" ] decodeElmHtml
        ]


{-| decode a node record
-}
decodeNode : Json.Decode.Decoder NodeRecord
decodeNode =
    Json.Decode.map4 NodeRecord
        (field "tag" Json.Decode.string)
        (field "children" (Json.Decode.list decodeElmHtml))
        (field "facts" decodeFacts)
        (field "descendantsCount" Json.Decode.int)


{-| encode a node record: currently does not support facts or children
-}
encodeNodeRecord : NodeRecord -> Json.Encode.Value
encodeNodeRecord record =
    Json.Encode.object
        [ ( "tag", Json.Encode.string record.tag )
          --, ( "children", Json.Encode.list encodeElmHtml)
          --, ( "facts", encodeFacts)
        , ( "descendantsCount", Json.Encode.int record.descendantsCount )
        ]


{-| decode custom node into either markdown or custom
-}
decodeCustomNode : Json.Decode.Decoder ElmHtml
decodeCustomNode =
    Json.Decode.oneOf
        [ Json.Decode.map MarkdownNode decodeMarkdownNodeRecord
        , Json.Decode.map CustomNode decodeCustomNodeRecord
        ]


{-| decode custom node record
-}
decodeCustomNodeRecord : Json.Decode.Decoder CustomNodeRecord
decodeCustomNodeRecord =
    Json.Decode.map2 CustomNodeRecord
        (field "facts" decodeFacts)
        (field "model" Json.Decode.value)


{-| decode markdown node record
-}
decodeMarkdownNodeRecord : Json.Decode.Decoder MarkdownNodeRecord
decodeMarkdownNodeRecord =
    Json.Decode.map2 MarkdownNodeRecord
        (field "facts" decodeFacts)
        (field "model" decodeMarkdownModel)


{-| decode the styles
-}
decodeStyles : Json.Decode.Decoder (Dict String String)
decodeStyles =
    Json.Decode.oneOf
        [ field styleKey (Json.Decode.dict Json.Decode.string)
        , Json.Decode.succeed Dict.empty
        ]


{-| encode styles
-}
encodeStyles : Dict String String -> Json.Encode.Value
encodeStyles stylesDict =
    let
        encodedDict =
            stylesDict
                |> Dict.toList
                |> List.map (\( k, v ) -> ( k, Json.Encode.string v ))
    in
        Json.Encode.object [ ( styleKey, Json.Encode.object encodedDict ) ]


{-| decode things which are not known using the given decoder for the value
-}
decodeOthers : Json.Decode.Decoder a -> Json.Decode.Decoder (Dict String a)
decodeOthers otherDecoder =
    (Json.Decode.dict Json.Decode.value)
        |> Json.Decode.andThen (filterKnownKeys
            >> Dict.toList
            >> List.filterMap
                (\( key, value ) ->
                    case Json.Decode.decodeValue otherDecoder value of
                        Err _ ->
                            Nothing

                        Ok v ->
                            Just ( key, v )
                )
            >> Dict.fromList
            >> Json.Decode.succeed
        )


{-| decode fact
-}
decodeFacts : Json.Decode.Decoder Facts
decodeFacts =
    Json.Decode.map6 Facts
        (decodeStyles)
        (Json.Decode.maybe (field eventKey Json.Decode.value))
        (Json.Decode.maybe (field attributeKey Json.Decode.value))
        (Json.Decode.maybe (field attributeNamespaceKey Json.Decode.value))
        (decodeOthers Json.Decode.string)
        (decodeOthers Json.Decode.bool)

{-| Just empty facts
-}
emptyFacts : Facts
emptyFacts =
    { styles = Dict.empty
    , events = Nothing
    , attributes = Nothing
    , attributeNamespace = Nothing
    , stringAttributes = Dict.empty
    , boolAttributes = Dict.empty
    }

