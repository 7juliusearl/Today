const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {chromium} = require('playwright');
(async () => {
  const browser = await chromium.launch({headless:true, ...(process.env.ASANA_TEST_CHROME ? {executablePath:process.env.ASANA_TEST_CHROME} : {})});
  try {
    const page = await browser.newPage();
    await page.setContent('<dialog open id="test"><button id="close">Close</button><div id="content"></div></dialog>');
    const source = fs.readFileSync(path.join(__dirname,'../../app.js'),'utf8');
    await page.addScriptTag({content: `
      const requests=[]; let fail=false;
      const original={id:'10',author:'Me',authorID:'1',editable:true,text:'Hello Alex',htmlText:'<body>Hello <a data-asana-gid="2">Alex</a></body>',createdAt:'2026-11-03T12:00:00Z'};
      window.webkit={messageHandlers:{asanaComments:{postMessage:async request=>{
        requests.push(request);
        if(request.action==='people') return {users:[{id:'2',name:'Alex'}]};
        if(request.action==='read') return {read:false};
        if(request.action==='edit') {if(fail)throw Error('Save failed');return {comments:[{...original,text:request.text,htmlText:'',edited:true}]};}
        return {comments:[original,{id:'11',author:'Other',editable:false,text:'Other comment',createdAt:'2026-11-03T12:01:00Z'}],next:''};
      }}}};
      function renderAsanaComment(el,c){el.textContent=c.text;}
      function asanaPersonColor(){}
      function asanaAvatar(){return document.createElement('span');}
      ${source.slice(source.indexOf('function asanaCommentDraft('),source.indexOf('function asanaAvatar('))}
      ${source.slice(source.indexOf('function asanaMentionPicker('))}
      addAsanaComments(document.getElementById('content'),{title:'Task',url:'https://app.asana.com/0/0/1',brief:{}},document.getElementById('test'),document.getElementById('close'));
    `});
    await page.waitForSelector('.asana-edit-comment');
    assert.equal(await page.locator('.asana-edit-comment').count(),1,'Only own comment editable');
    await page.locator('.asana-edit-comment').click();
    assert.equal(await page.getByRole('textbox',{name:'Edit your comment',exact:true}).inputValue(),'Hello @Alex');
    await page.getByRole('button',{name:'Cancel',exact:true}).click();
    assert.equal(await page.locator('.asana-comment-editor').count(),0);
    await page.locator('.asana-edit-comment').click();
    await page.getByRole('button',{name:'Save changes'}).click();
    await page.waitForSelector('.asana-comment-editor',{state:'detached'});
    const edit = await page.evaluate(()=>requests.find(r=>r.action==='edit'));
    assert.equal(edit.commentID,'10');assert.equal(edit.text,'Hello @Alex');assert.deepEqual(edit.mentions,[{id:'2',start:6,length:5}]);
    await page.evaluate(()=>fail=true);
    await page.locator('.asana-edit-comment').click();
    await page.getByRole('textbox',{name:'Edit your comment',exact:true}).fill('Keep my draft');
    await page.getByRole('button',{name:'Save changes'}).click();
    await page.getByRole('alert').filter({hasText:'Save failed'}).waitFor();
    assert.equal(await page.getByRole('textbox',{name:'Edit your comment',exact:true}).inputValue(),'Keep my draft');
    assert.equal(await page.getByRole('button',{name:'Save changes'}).isEnabled(),true);
    console.log('PASS: own-only edit control, cancel, save targets original comment, mention preservation, failed-save draft recovery.');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
