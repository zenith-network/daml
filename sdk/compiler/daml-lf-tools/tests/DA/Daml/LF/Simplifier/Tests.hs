-- Copyright (c) 2025 Digital Asset (Switzerland) GmbH and/or its affiliates. All rights reserved.
-- SPDX-License-Identifier: Apache-2.0

module DA.Daml.LF.Simplifier.Tests
    ( main
    ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.NameMap as NM
import qualified Data.Text as T

import DA.Daml.LF.Ast.Base
import DA.Daml.LF.Ast.Util
import DA.Daml.LF.Ast.Version (devLfVersion, Version, renderVersion)
import DA.Daml.LF.Ast.World (initWorld, initWorldSelf)
import DA.Daml.LF.Simplifier (simplifyModule)
import qualified DA.Daml.LF.TypeChecker as TypeChecker
import qualified Development.IDE.Types.Diagnostics as D


main :: IO ()
main = defaultMain $ testGroup "DA.Daml.LF"
    [ constantLiftingTests devLfVersion
    , externalCallTypeCheckerTests devLfVersion
    ]

-- The Simplifier calls the typechecker whose behavior is affected by feature
-- flags. The simplifier may thus behave differently based on the version of LF
-- and thus we may need to test different LF versions as they diverge over time.
constantLiftingTests :: Version -> TestTree
constantLiftingTests version = testGroup ("Constant Lifting " <> renderVersion version)
    [ mkTestCase "empty module" [] []
    , mkTestCase "closed value"
        [ dval "foo" TInt64 (EBuiltinFun (BEInt64 10)) ]
        [ dval "foo" TInt64 (EBuiltinFun (BEInt64 10)) ]
    , mkTestCase "nested int"
        [ dval "foo" (TInt64 :-> TInt64)
            (ETmLam (ExprVarName "x", TInt64) (EBuiltinFun (BEInt64 10))) ]
        [ dval "foo" (TInt64 :-> TInt64)
            (ETmLam (ExprVarName "x", TInt64) (EBuiltinFun (BEInt64 10))) ]
    , mkTestCase "nested arithmetic"
        [ dval "foo" (TInt64 :-> TInt64)
            (ETmLam (ExprVarName "x", TInt64)
                (EBuiltinFun BEAddInt64
                    `ETmApp` EBuiltinFun (BEInt64 10)
                    `ETmApp` EBuiltinFun (BEInt64 10)))
        ]
        [ dval "$$sc_foo_1" TInt64
            (EBuiltinFun BEAddInt64
                `ETmApp` EBuiltinFun (BEInt64 10)
                `ETmApp` EBuiltinFun (BEInt64 10))
        , dval "foo" (TInt64 :-> TInt64)
            (ETmLam (ExprVarName "x", TInt64) (exprVal "$$sc_foo_1"))
        ]
    , mkTestCase "\\xy.y" -- test that we aren't breaking up λxy.y into two lambdas.
        [ dval "foo" (TInt64 :-> TInt64 :-> TInt64)
            (ETmLam (ExprVarName "x", TInt64)
                (ETmLam (ExprVarName "y", TInt64)
                    (EVar (ExprVarName "y"))))
        ]
        [ dval "foo" (TInt64 :-> TInt64 :-> TInt64)
            (ETmLam (ExprVarName "x", TInt64)
                (ETmLam (ExprVarName "y", TInt64)
                    (EVar (ExprVarName "y"))))
        ]
    , mkTestCase "\\z.(\\xy.y)z" -- test that we're lifting closed lambda subexpressions
        [ dval "foo" (TInt64 :-> TInt64 :-> TInt64)
            (ETmLam (ExprVarName "z", TInt64)
                (ETmApp
                    (ETmLam (ExprVarName "x", TInt64)
                        (ETmLam (ExprVarName "y", TInt64)
                            (EVar (ExprVarName "y"))))
                    (EVar (ExprVarName "z"))))
        ]
        [ dval "$$sc_foo_1" (TInt64 :-> TInt64 :-> TInt64)
            (ETmLam (ExprVarName "x", TInt64)
                (ETmLam (ExprVarName "y", TInt64)
                    (EVar (ExprVarName "y"))))
        , dval "foo" (TInt64 :-> TInt64 :-> TInt64)
            (ETmLam (ExprVarName "z", TInt64)
                (ETmApp
                    (exprVal "$$sc_foo_1")
                    (EVar (ExprVarName "z"))))
            -- NOTE: this is a candidate for eta reduction, may be optimized in the future
        ]
    , mkTestCase "do not lift partial EXTERNAL_CALL heads"
        [ dval "partialExternalCall" (TText :-> TText :-> TUpdate TText)
            (ETmLam (ExprVarName "configHex", TText)
                (ETmLam (ExprVarName "inputValue", TText)
                    (EBuiltinFun BEExternalCall
                        `ETyApp` TText
                        `ETyApp` TText
                        `ETmApp` EBuiltinFun (BEText "ext")
                        `ETmApp` EBuiltinFun (BEText "fun")
                        `ETmApp` EVar (ExprVarName "configHex")
                        `ETmApp` EVar (ExprVarName "inputValue"))))
        ]
        [ dval "partialExternalCall" (TText :-> TText :-> TUpdate TText)
            (ETmLam (ExprVarName "configHex", TText)
                (ETmLam (ExprVarName "inputValue", TText)
                    (EBuiltinFun BEExternalCall
                        `ETyApp` TText
                        `ETyApp` TText
                        `ETmApp` EBuiltinFun (BEText "ext")
                        `ETmApp` EBuiltinFun (BEText "fun")
                        `ETmApp` EVar (ExprVarName "configHex")
                        `ETmApp` EVar (ExprVarName "inputValue"))))
        ]
    ]
  where
    mkTestCase :: String -> [DefValue] -> [DefValue] -> TestTree
    mkTestCase msg vs1 vs2 =
        testCase msg $ assertEqual "should be equal"
            vs2 (simplifyValues vs1)

    dval :: T.Text -> Type -> Expr -> DefValue
    dval name ty body = DefValue
        { dvalLocation = Nothing
        , dvalBinder = (ExprValName name, ty)
        , dvalBody = body
        }

    simplifyValues vs = NM.toList . moduleValues $
        simplifyModule world version Module
            { moduleName = ModuleName ["M"]
            , moduleSource = Nothing
            , moduleFeatureFlags = daml12FeatureFlags
            , moduleSynonyms = NM.empty
            , moduleDataTypes = NM.empty
            , moduleTemplates = NM.empty
            , moduleValues = NM.fromList vs
            , moduleExceptions = NM.empty
            , moduleInterfaces = NM.empty
            }
    world = initWorld [] version

    qualify :: t -> Qualified t
    qualify x = Qualified
        { qualPackage = SelfPackageId
        , qualModule = ModuleName ["M"]
        , qualObject = x
        }

    exprVal :: T.Text -> Expr
    exprVal = EVal . qualify . ExprValName

externalCallTypeCheckerTests :: Version -> TestTree
externalCallTypeCheckerTests version = testGroup ("External call type checker " <> renderVersion version)
    [ testCase "local aliases to EXTERNAL_CALL are rejected" $ do
        let diags = TypeChecker.checkPackage (initWorldSelf [] externalCallAliasPackage) version
        assertBool
            ("expected local EXTERNAL_CALL alias to be rejected, got: " <> show (map D._message diags))
            (any (T.isInfixOf "EXTERNAL_CALL must be used directly" . D._message) diags)
    , testCase "DA.External.externalCall names are not trusted by validation" $ do
        let diags = TypeChecker.checkPackage (initWorldSelf [] externalCallWrapperPackage) version
        assertBool
            ("expected polymorphic DA.External.externalCall wrapper to be rejected, got: " <> show (map D._message diags))
            (any (T.isInfixOf "expected serializable type:" . D._message) diags)
    ]
  where
    externalCallAliasPackage = Package
        { packageLfVersion = version
        , packageModules = NM.fromList [externalCallAliasModule]
        , packageMetadata = PackageMetadata (PackageName "external-call-typechecker-test") (PackageVersion "0.0.0") Nothing
        , importedPackages = Left $ noPkgImportsReasonTesting "DA.Daml.LF.Simplifier.Tests"
        }

    externalCallAliasModule = Module
        { moduleName = ModuleName ["M"]
        , moduleSource = Nothing
        , moduleFeatureFlags = daml12FeatureFlags
        , moduleSynonyms = NM.empty
        , moduleDataTypes = NM.empty
        , moduleTemplates = NM.empty
        , moduleValues = NM.fromList [externalCallAliasValue]
        , moduleExceptions = NM.empty
        , moduleInterfaces = NM.empty
        }

    externalCallAliasValue = DefValue
        { dvalLocation = Nothing
        , dvalBinder = (ExprValName "callThroughAlias", externalCallAliasType)
        , dvalBody =
            ETmLam (cidVar, contractIdUnitTy) $
            ELet
                (Binding (aliasVar, externalCallType) (EBuiltinFun BEExternalCall))
                (EVar aliasVar
                    `ETyApp` contractIdUnitTy
                    `ETyApp` TText
                    `ETmApp` EBuiltinFun (BEText "ext")
                    `ETmApp` EBuiltinFun (BEText "fun")
                    `ETmApp` EBuiltinFun (BEText "00")
                    `ETmApp` EVar cidVar)
        }

    externalCallAliasType = contractIdUnitTy :-> TUpdate TText
    contractIdUnitTy = TContractId TUnit
    cidVar = ExprVarName "cid"
    aliasVar = ExprVarName "f"
    inputVar = TypeVarName "input"
    outputVar = TypeVarName "output"
    externalCallType =
        TForall (inputVar, KStar) $
        TForall (outputVar, KStar) $
            TText :-> TText :-> TText :-> TVar inputVar :-> TUpdate (TVar outputVar)

    externalCallWrapperPackage = Package
        { packageLfVersion = version
        , packageModules = NM.fromList [externalCallWrapperModule]
        , packageMetadata = PackageMetadata (PackageName "external-call-wrapper-test") (PackageVersion "0.0.0") Nothing
        , importedPackages = Left $ noPkgImportsReasonTesting "DA.Daml.LF.Simplifier.Tests"
        }

    externalCallWrapperModule = Module
        { moduleName = ModuleName ["DA", "External"]
        , moduleSource = Nothing
        , moduleFeatureFlags = daml12FeatureFlags
        , moduleSynonyms = NM.empty
        , moduleDataTypes = NM.empty
        , moduleTemplates = NM.empty
        , moduleValues = NM.fromList [externalCallWrapperValue]
        , moduleExceptions = NM.empty
        , moduleInterfaces = NM.empty
        }

    externalCallWrapperValue = DefValue
        { dvalLocation = Nothing
        , dvalBinder = (ExprValName "externalCall", externalCallWrapperType)
        , dvalBody =
            ETyLam (inputVar, KStar) $
            ETyLam (outputVar, KStar) $
            ETmLam (ExprVarName "_serializableInput", TBool) $
            ETmLam (ExprVarName "_serializableOutput", TBool) $
            ETmLam (ExprVarName "extensionId", TText) $
            ETmLam (ExprVarName "functionId", TText) $
            ETmLam (ExprVarName "configHex", TText) $
            ETmLam (ExprVarName "inputValue", TVar inputVar) $
                EBuiltinFun BEExternalCall
                    `ETyApp` TVar inputVar
                    `ETyApp` TVar outputVar
                    `ETmApp` EVar (ExprVarName "extensionId")
                    `ETmApp` EVar (ExprVarName "functionId")
                    `ETmApp` EVar (ExprVarName "configHex")
                    `ETmApp` EVar (ExprVarName "inputValue")
        }

    externalCallWrapperType =
        TForall (inputVar, KStar) $
        TForall (outputVar, KStar) $
            TBool :-> TBool :-> TText :-> TText :-> TText :-> TVar inputVar :-> TUpdate (TVar outputVar)
