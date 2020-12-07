module Tracks.Collection.Internal.Arrange exposing (arrange)

import Conditional exposing (ifThenElse)
import Dict exposing (Dict)
import List.Extra as List
import Maybe.Extra as Maybe
import Playlists exposing (..)
import Playlists.Matching
import String.Ext as String
import Time
import Time.Ext as Time
import Tracks exposing (..)
import Tracks.Sorting as Sorting



-- 🍯


arrange : Parcel -> Parcel
arrange ( deps, collection ) =
    case deps.selectedPlaylist of
        Just playlist ->
            if playlist.autoGenerated then
                arrangeByGroup ( deps, collection )

            else
                arrangeByPlaylist ( deps, collection ) playlist

        Nothing ->
            arrangeByGroup ( deps, collection )



-- GROUPING


arrangeByGroup : Parcel -> Parcel
arrangeByGroup ( deps, collection ) =
    case deps.grouping of
        Just AddedOn ->
            ( deps, groupByInsertedAt deps collection )

        Just Directory ->
            ( deps, groupByDirectory deps collection )

        Just FirstAlphaCharacter ->
            ( deps, groupByFirstAlphaCharacter deps collection )

        Just TrackYear ->
            ( deps, groupByYear deps collection )

        Nothing ->
            collection.identified
                |> Sorting.sort deps.sortBy deps.sortDirection
                |> (\x -> { collection | arranged = x })
                |> (\x -> ( deps, x ))


addToList : a -> Maybe (List a) -> Maybe (List a)
addToList item maybeList =
    case maybeList of
        Just list ->
            Just (item :: list)

        Nothing ->
            Just [ item ]


groupBy : { reversed : Bool } -> (IdentifiedTrack -> Dict a (List IdentifiedTrack) -> Dict a (List IdentifiedTrack)) -> CollectionDependencies -> Collection -> Collection
groupBy { reversed } folder deps collection =
    collection.identified
        |> List.foldl folder Dict.empty
        |> Dict.values
        |> ifThenElse reversed List.reverse identity
        |> List.concatMap (Sorting.sort deps.sortBy deps.sortDirection)
        |> (\arranged -> { collection | arranged = arranged })



-- GROUPING  ░░  ADDED ON


groupByInsertedAt : CollectionDependencies -> Collection -> Collection
groupByInsertedAt =
    groupBy { reversed = True } groupByInsertedAtFolder


groupByInsertedAtFolder : IdentifiedTrack -> Dict Int (List IdentifiedTrack) -> Dict Int (List IdentifiedTrack)
groupByInsertedAtFolder ( i, t ) =
    let
        ( year, month ) =
            ( Time.toYear Time.utc t.insertedAt
            , Time.toMonth Time.utc t.insertedAt
            )

        group =
            { name = insertedAtGroupName year month
            , firstInGroup = False
            }

        item =
            ( { i | group = Just group }
            , t
            )
    in
    Dict.update
        (year * 1000 + Time.monthNumber month)
        (addToList item)


insertedAtGroupName : Int -> Time.Month -> String
insertedAtGroupName year month =
    if year == 1970 then
        "MANY MOONS AGO"

    else
        Time.monthName month ++ " " ++ String.fromInt year



-- GROUPING  ░░  DIRECTORY


groupByDirectory : CollectionDependencies -> Collection -> Collection
groupByDirectory deps =
    groupBy { reversed = False } (groupByDirectoryFolder deps) deps


groupByDirectoryFolder : CollectionDependencies -> IdentifiedTrack -> Dict String (List IdentifiedTrack) -> Dict String (List IdentifiedTrack)
groupByDirectoryFolder deps ( i, t ) =
    let
        prefix =
            case deps.selectedPlaylist of
                Just playlist ->
                    if playlist.autoGenerated then
                        playlist.name ++ "/"

                    else
                        ""

                _ ->
                    ""

        directory =
            t.path
                |> String.dropLeft (String.length prefix)
                |> String.chopStart "/"
                |> String.split "/"
                |> List.init
                |> Maybe.map (String.join " / ")
                |> Maybe.withDefault t.path

        group =
            { name = directory
            , firstInGroup = False
            }

        item =
            ( { i | group = Just group }
            , t
            )
    in
    Dict.update
        directory
        (addToList item)



-- GROUPING  ░░  FIRST LETTER


groupByFirstAlphaCharacter : CollectionDependencies -> Collection -> Collection
groupByFirstAlphaCharacter deps =
    groupBy { reversed = False } (groupByFirstAlphaCharacterFolder deps) deps


groupByFirstAlphaCharacterFolder : CollectionDependencies -> IdentifiedTrack -> Dict String (List IdentifiedTrack) -> Dict String (List IdentifiedTrack)
groupByFirstAlphaCharacterFolder deps ( i, t ) =
    let
        tag =
            case deps.sortBy of
                Artist ->
                    t.tags.artist

                Album ->
                    t.tags.album

                PlaylistIndex ->
                    ""

                Title ->
                    t.tags.title

        group =
            { name =
                tag
                    |> String.toList
                    |> List.head
                    |> Maybe.andThen
                        (\char ->
                            if Char.isAlpha char then
                                Just (String.fromList [ Char.toUpper char ])

                            else
                                Nothing
                        )
                    |> Maybe.withDefault "#"
            , firstInGroup = False
            }

        item =
            ( { i | group = Just group }
            , t
            )
    in
    Dict.update
        group.name
        (addToList item)



-- GROUPING  ░░  YEAR


groupByYear : CollectionDependencies -> Collection -> Collection
groupByYear =
    groupBy { reversed = True } groupByYearFolder


groupByYearFolder : IdentifiedTrack -> Dict Int (List IdentifiedTrack) -> Dict Int (List IdentifiedTrack)
groupByYearFolder ( i, t ) =
    let
        group =
            { name = Maybe.unwrap "0000 - Unknown" String.fromInt t.tags.year
            , firstInGroup = False
            }

        item =
            ( { i | group = Just group }
            , t
            )
    in
    Dict.update
        (Maybe.withDefault 0 t.tags.year)
        (addToList item)



-- PLAYLISTS


arrangeByPlaylist : Parcel -> Playlist -> Parcel
arrangeByPlaylist ( deps, collection ) playlist =
    collection.identified
        |> Playlists.Matching.match playlist
        |> dealWithMissingPlaylistTracks
        |> Sorting.sort PlaylistIndex Asc
        |> (\x -> { collection | arranged = x })
        |> (\x -> ( deps, x ))


dealWithMissingPlaylistTracks : ( List IdentifiedTrack, List IdentifiedPlaylistTrack ) -> List IdentifiedTrack
dealWithMissingPlaylistTracks ( identifiedTracks, remainingPlaylistTracks ) =
    identifiedTracks ++ List.map makeMissingPlaylistTrack remainingPlaylistTracks


makeMissingPlaylistTrack : IdentifiedPlaylistTrack -> IdentifiedTrack
makeMissingPlaylistTrack ( identifiers, playlistTrack ) =
    let
        tags =
            { disc = 1
            , nr = 0
            , artist = playlistTrack.artist
            , title = playlistTrack.title
            , album = playlistTrack.album
            , genre = Nothing
            , picture = Nothing
            , year = Nothing
            }
    in
    Tuple.pair
        { filename = ""
        , group = Nothing
        , indexInList = 0
        , indexInPlaylist = Just identifiers.index
        , isFavourite = False
        , isMissing = True
        , parentDirectory = ""
        }
        { tags = tags
        , id = missingId
        , insertedAt = Time.default
        , path = missingId
        , sourceId = missingId
        }
