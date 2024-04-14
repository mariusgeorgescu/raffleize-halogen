module App.WalletConnect where

import Effect.Aff.Class (class MonadAff)
import Contract.Prelude (Maybe(..))
import Data.Typelevel.Undefined (undefined)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE

-- import Select as Select
-- import Select.Setters as Setters
data WalletConnectAction
  = InitializeWallet
  | ExpandWalletsList

type WalletConnectState
  = { availableWallets :: Array String
    , connectedWallet :: Maybe String
    , walletsListExpanded :: Boolean
    }

component :: forall q i o m. (MonadAff m) => H.Component q i o m
component =
  H.mkComponent
    { initialState:
        \_ -> { availableWallets: [], connectedWallet: Nothing, walletsListExpanded: false }
    , render
    , eval:
        H.mkEval
          H.defaultEval
            { initialize = Just InitializeWallet
            , handleAction = handleAction
            }
    }

render :: forall m. WalletConnectState -> H.ComponentHTML WalletConnectAction () m
render { availableWallets, connectedWallet } = case connectedWallet of
  Just w -> undefined
  Nothing ->
    HH.button
      [ HE.onClick \_ -> ExpandWalletsList ]
      [ HH.text "Connect" ]

handleAction = undefined
