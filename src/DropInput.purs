module DropInput where

import Prelude
import Color as Color
import Data.Either (Either(..))
import Data.Foldable as Foldable
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Show (genericShow)
import Data.Maybe (Maybe(..))
import Data.Nullable as Nullable
import Effect (Effect)
import Effect.Aff as Aff
import Jira (CSV(..))
import Jira as Jira
import React.Basic.DOM as R
import React.Basic.DOM.Events as DOM.Events
import React.Basic.Events as Events
import React.Basic.Hooks (Component, (/\))
import React.Basic.Hooks as Hooks
import Text.Parsing.CSV as CSV
import Text.Parsing.Parser (ParseError)
import Text.Parsing.Parser as Parser
import Web.File.File (File)
import Web.File.File as File
import Web.File.FileList as FileList
import Web.File.FileReader.Aff as FileReader.Aff
import Web.HTML.Event.DataTransfer as DataTransfer
import Web.HTML.Event.DataTransfer.DataTransferItem as DataTransferItem
import Web.HTML.Event.DataTransfer.Ext as DataTransfer.Ext
import Web.HTML.Event.DragEvent as DragEvent
import Web.HTML.HTMLElement as HTMLElement
import Web.HTML.HTMLInputElement as HTMLInputElement

type ParsedState a
  = Maybe (Either ParseError a)

data HoverState
  = NotHovering
  | HoveringWithWarning
  | Hovering

derive instance genericHoverState :: Generic (HoverState) _

instance showHoverState :: Show (HoverState) where
  show = genericShow

parseCSV :: String -> ParsedState String
parseCSV str = case Parser.runParser str CSV.defaultParsers.file of
  Left parseError -> Just (Left parseError)
  Right csv -> case Jira.csvToPrintedGraph (CSV csv) of
    Nothing -> Nothing
    Just x -> Just (Right x)

mkDropInput :: Component (String -> Effect Unit)
mkDropInput =
  Hooks.component "DropInput" \handleCSV -> Hooks.do
    hover /\ setHover <- Hooks.useState' NotHovering
    parsedCSV /\ setParsedCSV <- Hooks.useState' Nothing
    fileInputRef <- Hooks.useRef Nullable.null
    Hooks.useEffect parsedCSV do
      (Foldable.traverse_ <<< Foldable.traverse_) handleCSV parsedCSV
      pure mempty
    let
      onButtonClick =
        Events.handler_ do
          maybeNode <- Hooks.readRefMaybe fileInputRef
          Foldable.for_ (HTMLElement.fromNode =<< maybeNode) \htmlElement -> do
            HTMLElement.click htmlElement

      handleReadFile :: File -> Effect Unit
      handleReadFile file' = do
        let
          blob = File.toBlob file'
        Aff.runAff_
          (Foldable.traverse_ setParsedCSV <<< (parseCSV <$> _))
          (FileReader.Aff.readAsText blob)

      mkBlue = Color.hsla 203.0 1.0 0.5

      mkRed = Color.hsla 13.0 1.0 0.5

      mkGray = Color.hsla 0.0 0.0 0.5
    pure do
      R.div
        { style:
            R.css
              { display: "flex"
              , flexDirection: "column"
              , alignItems: "center"
              , justifyContent: "center"
              , borderRadius: "1rem"
              , inlineSize: "calc(100% - 4rem)"
              , blockSize: "calc(100% - 4rem)"
              , borderWidth: "0.4rem"
              , margin: "auto"
              , borderStyle: "dashed"
              , borderColor:
                  Color.cssStringHSLA case hover of
                    Hovering -> mkBlue 1.0
                    HoveringWithWarning -> mkRed 1.0
                    NotHovering -> mkGray 0.5
              , backgroundColor:
                  Color.cssStringHSLA case hover of
                    Hovering -> mkBlue 0.1
                    HoveringWithWarning -> mkRed 0.2
                    NotHovering -> mkGray 0.0
              }
        , onDragEnter:
            Events.handler_ do
              setHover Hovering
        , onDragLeave:
            Events.handler_ do
              setHover NotHovering
        , onDragOver:
            DOM.Events.capture DOM.Events.nativeEvent \event -> do
              -- _ <- pure (Debug.spy "event" event)
              -- TODO: Give feedback when user is dragging an item, as to 
              -- whether that item will be accepted (is a CSV) or not
              -- Probably need to use FFI, something to the effect of
              -- ```js
              -- dataTransfer.items[0].type === "text/csv"
              -- ```
              --
              let
                maybeItem =
                  DragEvent.fromEvent event
                    >>= DragEvent.dataTransfer
                    >>> DataTransfer.Ext.items
                    >>> DataTransferItem.dataTransferItem 0
                    <#> DataTransferItem.type_
              setHover Hovering
        , onDrop:
            DOM.Events.capture DOM.Events.nativeEvent \e -> do
              setHover NotHovering
              let
                maybeFileList = DataTransfer.files =<< DragEvent.dataTransfer <$> DragEvent.fromEvent e
              Foldable.for_ (FileList.item 0 =<< maybeFileList) handleReadFile
        , children:
            [ R.button
                { onClick: onButtonClick
                , children: [ R.text "Import CSV" ]
                }
            , R.input
                { ref: fileInputRef
                , hidden: true
                , type: "file"
                , multiple: false
                , accept: ".csv"
                , onChange:
                    Events.handler DOM.Events.currentTarget \target ->
                      Foldable.for_ (HTMLInputElement.fromEventTarget target) \fileInput -> do
                        maybeFileList <- HTMLInputElement.files fileInput
                        Foldable.for_ (FileList.item 0 =<< maybeFileList) handleReadFile
                }
            ]
        }
