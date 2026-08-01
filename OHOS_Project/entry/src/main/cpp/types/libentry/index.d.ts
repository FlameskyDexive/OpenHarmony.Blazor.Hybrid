import { webview } from '@kit.ArkWeb';

export type InterceptResponseFactory = (code: number, message: string, mimeType: string, buffer: ArrayBuffer) => WebResourceResponse;
export type SendMessageCallback = (message: string) => void;
export type NavigateCallback = (url: string) => void;

export const interceptRequest: (url: string, createResponse: InterceptResponseFactory) => WebResourceResponse;

export const createBlazor: (sendMessage: SendMessageCallback, navigateCore: NavigateCallback) => void;

export const messageReceive: (message: string) => void;

export const onFrame: () => void;
