/**
 * MIT License
 *
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import { RNComponentContext } from '@rnoh/react-native-openharmony';
import webview from '@ohos.web.webview';
import { url as OSUrl } from '@kit.ArkTS';
import { RNC } from '@rnoh/react-native-openharmony/generated';
import Logger from './Logger';
import { BaseOperate } from './WebViewBaseOperate';
import {
  AlertEvent,
  CACHE_MODE,
  JAVASCRIPT_INTERFACE,
  ONE_HUNDRED,
  ResultType,
  RNCWebViewBridge,
  WebViewEventParams,
  WebViewNewSource,
  WebViewOverScrollMode,
  ZERO
} from './Magic';

export const TAG = "WebView"

export const WEB_VIEW = "RNCWebView"

@Component
export struct RNCWebView {
  public static readonly NAME = RNC.RNCWebView.NAME
  ctx!: RNComponentContext
  tag: number = ZERO
  source: WebViewNewSource = {
    uri: "",
    method: "",
    body: "",
    html: "",
    baseUrl: ""
  }
  html: string | undefined = "";
  url: string | Resource = "";
  controller: webview.WebviewController = new webview.WebviewController();
  javaScriptEnable: boolean = true;
  allowFileAccess: boolean = true;
  overScrollMode: OverScrollMode = OverScrollMode.NEVER;
  progress: number = ZERO;
  cacheMode: number = CacheMode.Default;
  lockIdentifier: string = "";
  requestUrl: string = "";
  messagingEnabled: boolean = false;
  hasRegisterJavaScriptProxy: boolean = false;
  controllerAttached: boolean = false;
  renderMode: RenderMode = RenderMode.SYNC_RENDER;
  scrollEnabled = true;
  nestedScroll = NestedScrollMode.SELF_FIRST;
  headers: Array<webview.WebHeader> = []
  injectedJavaScriptBeforeContentLoaded: Array<ScriptItem> = [
    { script: '', scriptRules: ["*"] }
  ];
  allowPageStartInProgress = true;
  @State webviewWidth: number = ZERO
  @State webviewHeight: number = ZERO
  private unregisterDescriptorChangesListener?: () => void = undefined
  private cleanupCommandCallback?: () => void = undefined
  private eventEmitter: RNC.RNCWebView.EventEmitter | undefined = undefined
  private cleanUpCallbacks: (() => void)[] = []
  private descriptorWrapper: RNC.RNCWebView.DescriptorWrapper = {} as RNC.RNCWebView.DescriptorWrapper
  private webViewBaseOperate: BaseOperate | null = null

  aboutToAppear() {
    try {
      this.initVariable()
      this.url = this.source.uri as string;
      webview.WebviewController.setWebDebuggingAccess(this.descriptorWrapper.props.webviewDebuggingEnabled)
      this.cleanUpCallbacks.push(this.ctx.descriptorRegistry.subscribeToDescriptorChanges(this.tag,
        (_descriptor, newDescriptorWrapper) => {
          this.onDescriptorWrapperChange(newDescriptorWrapper! as RNC.RNCWebView.DescriptorWrapper)
        }
      ))
      this.registerCommandCallback()
      if (this.hasIncognito()) {
        this.cacheMode = CacheMode.Online;
      }
      if (this.source.headers) {
        this.source.headers.forEach(item => {
          if (item.name && item.value) {
            this.headers.push({ headerKey: item.name, headerValue: item.value })
          }
        })
      }
    } catch (error) {
      Logger.error(TAG, `[RNOH]Errorcode: ${error.code}, Message: ${error.message}`);
    }

  }

  hasIncognito(): boolean {
    return this.descriptorWrapper.props.incognito && this.descriptorWrapper.props.incognito === true
  }

  createWebViewEvent(type: string): WebViewEventParams {
    return this.webViewBaseOperate?.createWebViewEvent({ type, progress: this.progress }) as WebViewEventParams;
  }

  aboutToDisappear() {
    this.cleanupCommandCallback?.()
    this.unregisterDescriptorChangesListener?.()
    Logger.debug(TAG, `[RNOH] aboutToDisappear`)
    this.cleanUpCallbacks.forEach(cb => cb())
    try {
      if (this.hasIncognito()) {
        this.controller.clearHistory()
        webview.WebCookieManager.clearAllCookiesSync(true);
        webview.WebCookieManager.clearSessionCookieSync()
        webview.WebStorage.deleteAllData();
      }
      this.controller.deleteJavaScriptRegister(JAVASCRIPT_INTERFACE)
      this.controller.refresh()
      this.hasRegisterJavaScriptProxy = false
      this.webViewBaseOperate = null
    } catch (error) {
      Logger.error(TAG, `[RNOH]Errorcode: ${error.code}, Message: ${error.message}`);
    }
  }

  registerCommandCallback() {
    this.cleanupCommandCallback = this.ctx.componentCommandReceiver.registerCommandCallback(
      this.tag,
      (command, args: string[]) => {
        switch (command) {
          case "injectJavaScript":
            Logger.debug(TAG, `[RNOH] injectJavaScript,${JSON.stringify(args)}`)
            if (this.controllerAttached) {
              try {
                this.controller.runJavaScript("(function() {\n" + args[0] + ";\n})();")
              } catch (error) {
                Logger.error(TAG, "error: " + error)
              }
            }
            break
          case "postMessage":
            Logger.debug(TAG, `[RNOH] postMessage,${JSON.stringify(args)}`)
            let data = JSON.stringify({ data: args[0] })
            let result: string = "(function () {" +
              "var event;" +
              "var data = " + data.toString() + ";" +
              "try {" +
              "event = new MessageEvent('message', data);" +
              "} catch (e) {" +
              "event = document.createEvent('MessageEvent');" +
              "event.initMessageEvent('message', true, true, data.data, data.origin, data.lastEventId, data.source);" +
              "}" +
              "document.dispatchEvent(event);" +
              "})();"
            if (this.controllerAttached) {
              try {
                this.controller.runJavaScript(result)
              } catch (error) {
                Logger.error(TAG, "error:" + error)
              }
            }
            break;
          case "reload":
            Logger.debug(TAG, `[RNOH] reload,${JSON.stringify(args)}`)
            if (this.controllerAttached) {
              try {
                this.controller.refresh();
              } catch (error) {
                Logger.error(TAG, "error: " + error)
              }
            }
            break
          case "goBack":
            Logger.debug(TAG, `[RNOH] goBack,${JSON.stringify(args)}`)
            if (this.controllerAttached) {
              try {
                this.controller.backward();
              } catch (error) {
                Logger.error(TAG, "error: " + error)
              }
            }
            break
          case "goForward":
            Logger.debug(TAG, `[RNOH] goForward,${JSON.stringify(args)}`)
            if (this.controllerAttached) {
              try {
                this.controller.forward();
              } catch (error) {
                Logger.error(TAG, "error: " + error)
              }
            }
            break
          case "requestFocus":
            Logger.debug(TAG, `[RNOH] requestFocus,${JSON.stringify(args)}`)
            if (this.controllerAttached) {
              try {
                this.controller.requestFocus();
              } catch (error) {
                Logger.error(TAG, "error: " + error)
              }
            }
            break
          case "clearCache":
            Logger.debug(TAG, `[RNOH] clearCache,${JSON.stringify(args)}`)
            if (this.controllerAttached) {
              try {
                const removeFlag = !!args[0] === true;
                this.controller.removeCache(removeFlag);
              } catch (error) {
                Logger.error(TAG, "error: " + error)
              }
            }
            break
          case "clearHistory":
            Logger.debug(TAG, `[RNOH] clearHistory,${JSON.stringify(args)}`)
            if (this.controllerAttached) {
              try {
                this.controller.clearHistory();
              } catch (error) {
                Logger.error(TAG, "error: " + error)
              }
            }
            break
          default:
            break
        }
      });
  }

  onLoadingStart() {
    this.webViewBaseOperate?.emitLoadingStart({ progress: this.progress })
  }

  onProgressChange() {
    // 修复单页面应用切换路由时 onPageBegin 未触发的问题
    if (this.controller.getUrl() !== this.url && this.progress < ONE_HUNDRED && this.allowPageStartInProgress) {
      this.allowPageStartInProgress = false;
      this.onLoadingStart();
    }
    this.webViewBaseOperate?.emitProgressChange({ progress: this.progress })
    if (this.progress === ONE_HUNDRED) {
      this.allowPageStartInProgress = true;
    }
  }

  onLoadingFinish() {
    this.webViewBaseOperate?.emitLoadingFinish({ progress: this.progress })
  }

  onLoadingError(code: number, description: string) {
    this.webViewBaseOperate?.emitLoadingError({ code, description })
  }

  onHttpError(code: number, description: string) {
    this.webViewBaseOperate?.emitHttpError({ code, description })
  }

  scroll(x: number, y: number) {
    this.webViewBaseOperate?.emitScroll({ x, y })
  }

  onShouldStartLoadWithRequest() {
    this.webViewBaseOperate?.emitShouldStartLoadWithRequest({ progress: this.progress })
  }

  runInjectedJavaScript() {
    let injectedJS = this.descriptorWrapper.props.injectedJavaScript
    if (this.javaScriptEnable && injectedJS != "" && this.controllerAttached) {
      try {
        this.controller.runJavaScript("(function() {\n" + injectedJS + ";\n})();")
          .then((result) => {
            Logger.debug(TAG, '[RNOH] result: ' + result);
          })
          .catch((error: string | Error) => {
            Logger.error(TAG, "[RNOH] error: " + error);
          })
      } catch (error) {
        Logger.error(TAG, `[RNOH]Errorcode: ${error.code}, Message: ${error.message}`);
      }
    }
  }

  getJsDialogTitle() {
    const url = this.controller.getUrl()
    // 对于 data: URL，只显示 'JavaScript'，类似于 Chrome
    let title = 'JavaScript';
    const isDataUrl = (url !== null) && url.startsWith("data:");


    if (!isDataUrl) {
      try {
        const dialogUrl = OSUrl.URL.parseURL(url);
        title = `网址为”${dialogUrl.protocol}//${dialogUrl.host}“的网页显示：`;
      } catch (ex) {
        title = url;
      }
    }

    return title;
  }

  onJavascriptAlert(event?: AlertEvent) {
    if (event) {
      AlertDialog.show({
        title: this.getJsDialogTitle(),
        message: event.message,
        alignment: DialogAlignment.Center,
        secondaryButton: {
          value: '确定',
          action: () => event.result.handleConfirm()
        },
        cancel: () => event.result.handleCancel(),
      })
    }
    return true
  }

  onJavascriptConfirm(event?: AlertEvent) {
    if (event) {
      AlertDialog.show({
        title: this.getJsDialogTitle(),
        message: event.message,
        alignment: DialogAlignment.Center,
        secondaryButton: {
          value: '确定',
          action: () => event.result.handleConfirm()
        },
        cancel: () => event.result.handleCancel(),
        primaryButton: {
          value: '取消',
          action: () => event.result.handleCancel()
        },
      })
    }
    return true
  }

  ignoreSilentHardwareSwitchMethods(ignoreSilentHardwareSwitch: boolean) {
    this.webViewBaseOperate?.ignoreSilentHardwareSwitchMethods(ignoreSilentHardwareSwitch)
  }

  controllerAttachedInit(): void {
    this.controllerAttached = true;
    this.eventEmitter = new RNC.RNCWebView.EventEmitter(this.ctx.rnInstance, this.tag)
    this.webViewBaseOperate = new BaseOperate(this.eventEmitter, this.controller)

  }

  onPageBeginInit() {
    try {
      this.onLoadingStart()
      this.controller.setScrollable(this.scrollEnabled)
      this.ignoreSilentHardwareSwitchMethods(this.descriptorWrapper.props.ignoreSilentHardwareSwitch)
      if (this.descriptorWrapper.props.userAgent) {
        this.controller.setCustomUserAgent(this.descriptorWrapper.props.userAgent);
      } else {
        // 修复一些页面下无法将鸿蒙userAgent识别为手机的问题
        let userAgent: string = this.controller.getUserAgent() + ' iPhone';
        this.controller.setCustomUserAgent(userAgent);
      }
    } catch (error) {
      Logger.debug(TAG,
        `[RNOH] setCustomUserAgent ErrorCode: ${error.code},  Message: ${error.message}, userAgent: ${this.descriptorWrapper.props.userAgent}`);
    }
  }

  build() {
    Stack() {
      Web({ src: "", controller: this.controller, renderMode: this.renderMode })
        .width(this.webviewWidth)
        .height(this.webviewHeight)
        .fileAccess(this.allowFileAccess)
        .constraintSize({ minHeight: 1 })
        .overScrollMode(this.overScrollMode)
        .backgroundColor(Color.Transparent)
        .javaScriptAccess(this.javaScriptEnable)
        .javaScriptOnDocumentStart(this.injectedJavaScriptBeforeContentLoaded)
        .horizontalScrollBarAccess(this.descriptorWrapper.props.showsHorizontalScrollIndicator)
        .verticalScrollBarAccess(this.descriptorWrapper.props.showsVerticalScrollIndicator)
        .overviewModeAccess(this.descriptorWrapper.props.scalesPageToFit)
        .textZoomRatio(this.descriptorWrapper.props.textZoom)
        .cacheMode(this.cacheMode)
        .domStorageAccess(this.descriptorWrapper.props.domStorageEnabled)
        .zoomAccess(this.descriptorWrapper.props.scalesPageToFit)
        .overScrollMode(this.overScrollMode)
        .onProgressChange((event) => {
          if (event) {
            this.progress = event.newProgress
            this.onProgressChange()
          }
        })
        .onScroll((event) => {
          if (event) {
            this.scroll(event.xOffset, event.yOffset)
          }
        })
        .nestedScroll({
          scrollForward: this.nestedScroll,
          scrollBackward: this.nestedScroll,
        })
        .onPageBegin(() => {
          this.onPageBeginInit()
        })
        .onPageEnd(() => {
          Logger.debug(TAG, "[RNOH] onPageEnd")
          this.runInjectedJavaScript()
          this.onLoadingFinish()
        })
        .onErrorReceive((event) => {
          if (event) {
            let errorInfo: string = event.error.getErrorInfo();
            let errorCode: number = event.error.getErrorCode();
            Logger.debug(TAG, "[RNOH] errorInfo:" + errorInfo)
            Logger.debug(TAG, "[RNOH] errorCode:" + errorCode)
            this.onLoadingError(errorCode, errorInfo)
          }
        })
        .onHttpErrorReceive((event) => {
          if (event) {
            let errorInfo: string = event.response.getResponseData();
            let code: number = event.response.getResponseCode()
            Logger.debug(TAG, "[RNOH] errorInfo:" + errorInfo)
            this.onHttpError(code, errorInfo)
          }
        })
        .onControllerAttached(() => {
          this.controllerAttachedInit()
          Logger.debug(TAG, "[RNOH] onControllerAttached")
          let baseUrl = this.source.baseUrl
          let uri = this.source.uri
          if (this.source.html != undefined && this.source.html != "") {
            try {
              this.controller.loadData(
                this.source.html,
                "text/html",
                "UTF-8",
                baseUrl,
                " "
              );
            } catch (error) {
              Logger.error(TAG, "error:" + error)
            }
          } else if (uri != undefined && uri != "") {
            this.controller.loadUrl(uri, this.headers);
          } else {
            this.controller.loadUrl(uri, this.headers);
          }
          if (!this.hasRegisterJavaScriptProxy) {
            this.registerPostMessage()
          }
        })
        .onAlert((event) => this.onJavascriptAlert(event))
        .onConfirm((event) => this.onJavascriptConfirm(event))
    }
    .width(this.webviewWidth)
    .height(this.webviewHeight)
    .position({
      x: this.descriptorWrapper.positionRelativeToParent.x,
      y: this.descriptorWrapper.positionRelativeToParent.y
    })
  }

  private onDescriptorWrapperChange(descriptorWrapper: RNC.RNCWebView.DescriptorWrapper) {
    this.initVariable()
    this.descriptorWrapper = descriptorWrapper
    if (this.html != "" && this.html != this.source.html) {
      Logger.debug(TAG, "[RNOH] html is update")
      this.html = this.source.html
      if (this.controllerAttached) {
        try {
          this.controller.loadData(
            this.source.html,
            "text/html",
            "UTF-8",
            this.source.baseUrl,
            " "
          );
        } catch (error) {
          Logger.error(TAG, "error: " + error)
        }
      }
    } else if (this.source.uri != "" && this.url != this.source.uri) {
      Logger.debug(TAG, `[RNOH] newDescriptor props update uri: ` + this.source.uri);
      this.url = this.source.uri as string;
      if (this.controllerAttached) {
        this.controller.loadUrl(this.descriptorWrapper.props.newSource.uri, this.headers)
      }
    }
    if (this.controllerAttached) {
      this.controller?.setScrollable(this.descriptorWrapper.props.scrollEnabled)
    }
  }

  private initVariable() {
    this.descriptorWrapper =
      this.ctx.descriptorRegistry.findDescriptorWrapperByTag<RNC.RNCWebView.DescriptorWrapper>(this.tag)!
    this.javaScriptEnable = this.descriptorWrapper.props.javaScriptEnabled;
    this.cacheMode =
      this.descriptorWrapper.props.cacheEnabled ?
        this.webViewBaseOperate?.transCacheMode(this.descriptorWrapper.props.cacheMode as CACHE_MODE) as number :
      CacheMode.Online;
    this.source = {
      uri: this.descriptorWrapper.props.newSource.uri ?? "",
      method: this.descriptorWrapper.props.newSource.method ?? "",
      body: this.descriptorWrapper.props.newSource.body ?? "",
      html: this.descriptorWrapper.props.newSource.html ?? "",
      baseUrl: this.descriptorWrapper.props.newSource.baseUrl ?? "",
      headers: this.descriptorWrapper.props.newSource.headers ?? []
    }
    if (this.source.headers) {
      this.source.headers.forEach(item => {
        if (item.name && item.value) {
          this.headers.push({ headerKey: item.name, headerValue: item.value })
        }
      })
    }
    this.html = this.source.html
    this.webviewWidth = this.descriptorWrapper.width
    this.webviewHeight = this.descriptorWrapper.height
    this.scrollEnabled = this.descriptorWrapper.props.scrollEnabled;
    // 当禁止滚动时，使用父组件滚动
    this.nestedScroll = this.scrollEnabled ? NestedScrollMode.SELF_FIRST : NestedScrollMode.PARENT_FIRST;
    if (this.source.uri && this.source.uri.toString().startsWith("asset://")) {
      this.source.uri = $rawfile(this.source.uri.toString().replace("asset://", this.ctx.rnInstance.getAssetsDest()));
    }

    if (this.descriptorWrapper.props.overScrollMode === WebViewOverScrollMode.ALWAYS) {
      this.overScrollMode = OverScrollMode.ALWAYS
    } else if (this.descriptorWrapper.props.overScrollMode === WebViewOverScrollMode.NEVER) {
      this.overScrollMode = OverScrollMode.NEVER
    }

    this.overScrollMode = this.descriptorWrapper.props.bounces ? OverScrollMode.ALWAYS : OverScrollMode.NEVER;

    if (this.descriptorWrapper.props.injectedJavaScriptBeforeContentLoaded) {
      this.injectedJavaScriptBeforeContentLoaded = [
        { script: this.descriptorWrapper.props.injectedJavaScriptBeforeContentLoaded, scriptRules: ["*"] }
      ];
    }
  }

  private registerPostMessage() {
    if (this.messagingEnabled == this.descriptorWrapper.props.messagingEnabled) {
      return;
    }
    this.messagingEnabled = this.descriptorWrapper.props.messagingEnabled;
    if (this.messagingEnabled) {
      let bridge: RNCWebViewBridge = {
        postMessage: (data: string) => {
          Logger.debug(TAG, `[RNOH] bridge postMessage,  ${JSON.stringify(data)}`);
          if (this.controller != null) {
            let result: WebViewEventParams = this.createWebViewEvent("onMessage")
            result.data = data.toString()
            result.lockIdentifier = ZERO
            this.eventEmitter!.emit("message", result as ResultType);
          }
        }
      };
      this.controller.registerJavaScriptProxy(bridge, JAVASCRIPT_INTERFACE, ["postMessage"])
      this.source.uri ?
      this.controller.loadUrl(this.source.uri, this.headers) : this.controller.refresh()
      this.hasRegisterJavaScriptProxy = true
    }
  }
}