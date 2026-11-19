/** Electron owns OS differences; capabilities stay explicit at the service boundary. */
export function createHost({app,clipboard,Notification,window}) {
  return {
    describe:()=>({id:{win32:'windows',darwin:'macos',linux:'linux'}[process.platform]??'unsupported',
      capabilities:{clipboard:'supported',alwaysOnTop:'supported',notification:Notification.isSupported()?'supported':'unsupported',
        inputInjection:'unsupported',bluetooth:'unsupported',microphone:'unsupported'}}),
    copy(text) {if (typeof text!=='string' || text.length>1000) throw new Error('文本无效'); clipboard.writeText(text);},
    alwaysOnTop(enabled) {if (typeof enabled!=='boolean') throw new Error('置顶参数无效'); window.setAlwaysOnTop(enabled);},
    notify() {if(Notification.isSupported()) new Notification({title:app.name,body:'手表陪伴客户端已就绪'}).show();}
  };
}
