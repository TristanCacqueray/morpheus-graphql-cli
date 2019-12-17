{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}

module Rendering.Values
  ( renderRootResolver
  , renderResolver
  , Scope(..)
  )
where

import           Data.Semigroup                 ( (<>) )
import           Data.Text                      ( Text )

-- MORPHEUS
import           Rendering.Terms                ( Context(..)
                                                , Scope(..)
                                                , renderAssignment
                                                , renderCon
                                                , renderEqual
                                                , renderReturn
                                                , renderSet
                                                , renderUnionCon
                                                , ioRes
                                                , newline
                                                )
import           Data.Morpheus.Types.Internal.AST
                                                ( DataField(..)
                                                , DataType(..)
                                                , DataTypeContent(..)
                                                , DataTypeLib(..)
                                                , DataEnumValue(..)
                                                , TypeRef(..)
                                                , TypeWrapper(..)
                                                )

renderRootResolver :: Context -> DataTypeLib -> Text
renderRootResolver Context { pubSub = (channel, _) } DataTypeLib { mutation, subscription }
  = renderSignature <> renderBody
 where
  renderSignature = "rootResolver :: " <> renderRootSig <> "\n"
   where
    renderRootSig =
      "GQLRootResolver IO "
        <> channel
        <> " Query "
        <> maybeOperation mutation
        <> " "
        <> maybeOperation subscription
    ----------------------
    maybeOperation (Just (name, _)) = name
    maybeOperation Nothing          = "Undefined"
  renderBody = "rootResolver =\n  GQLRootResolver" <> renderResObject fields
   where
    fields =
      [ ("queryResolver"       , "resolveQuery")
      , ("mutationResolver"    , maybeRes mutation)
      , ("subscriptionResolver", maybeRes subscription)
      ]
  ---------------------------------------------
    maybeRes (Just (name, _)) = "resolve" <> name
    maybeRes Nothing          = "Undefined"

renderResolver :: Context -> (Text, DataType) -> Text
renderResolver Context { scope, pubSub = (channel, content) } (name, DataType { typeName, typeContent })
  = renderSig typeContent
 where
  renderSig DataScalar{} =
    defFunc <> renderReturn <> "$ " <> renderCon name <> "0 0"
  renderSig (DataEnum enums) =
    defFunc <> renderReturn <> renderCon (enumName $ head enums)
  renderSig (DataUnion (member : _)) =
    defFunc <> renderUnionCon typeName member <> " <$> " <> "resolve" <> member
  renderSig (DataObject fields) =
    defFunc <> renderReturn <> renderCon name <> renderObjFields
   where
    renderObjFields = renderResObject (map renderFieldRes fields)
    renderFieldRes (key, DataField { fieldType = TypeRef { typeWrappers, typeConName } })
      = ( key
        , "const " <> withScope scope (renderValue typeWrappers typeConName)
        )
     where
      renderValue (TypeMaybe : _) = const $ "$ " <> renderReturn <> "Nothing"
      renderValue (TypeList  : _) = const $ "$ " <> renderReturn <> "[]"
      renderValue []              = fieldValue
      ----------------------------------------------------------------------------
      fieldValue "String" = "$ return \"\""
      fieldValue "Int"    = "$ return 0"
      fieldValue fName    = "resolve" <> fName
      -------------------------------------------
      withScope Subscription x =
        "$ Event { channels = [Channel], content = const " <> x <> " }"
      withScope Mutation x = case (channel, content) of
        ("()", "()") -> x
        _ ->
          "$ toMutResolver [Event {channels = [Channel], content = Content}] "
            <> x
      withScope _ x = x
  renderSig _ = "" -- INPUT Types Does not Need Resolvers
  --------------------------------
  defFunc = renderSignature <> renderFunc
  ----------------------------------------------------------------------------------------------------------
  renderSignature =
    renderAssignment ("resolve" <> name) (renderMonad name) <> "\n"
  ---------------------------------------------------------------------------------
  renderMonad "Mutation" =
    "IOMutRes " <> channel <> " " <> content <> " Mutation"
  renderMonad "Subscription" = "SubRootRes IO " <> channel <> " Subscription"
  renderMonad tName          = ioRes channel <> tName
  ----------------------------------------------------------------------------------------------------------
  renderFunc = "resolve" <> name <> " = "
    ---------------------------------------

renderResObject :: [(Text, Text)] -> Text
renderResObject = renderSet . map renderEntry
  where renderEntry (key, value) = renderEqual key value
