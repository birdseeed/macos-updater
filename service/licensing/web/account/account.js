'use strict';
(() => {
 const root='/__fixture/web/account';
 const el=id=>document.getElementById(id);
 let confirmed=null,generation=0,readSerial=0,pending=false,target=null;
 const message=text=>{el('account-message').textContent=text;};
 const error=text=>{el('account-error').textContent=text;};
 function suffix(mac,macs){let length=6;while(length<32&&macs.some(other=>other.activationID!==mac.activationID&&other.displayName===mac.displayName&&other.activationID.slice(-length)===mac.activationID.slice(-length)))length++;return mac.activationID.slice(-length);}
 function label(mac){return mac.displayName+' · '+suffix(mac,confirmed.slots.macs);}
 function controls(){
  el('start-trial').disabled=pending||!confirmed||confirmed.reauthRequired||!confirmed.licence.trialAvailable;
  el('logout-account').disabled=pending||!confirmed;
  for(const button of el('mac-list').querySelectorAll('button'))button.disabled=pending||!confirmed||confirmed.reauthRequired;
  el('confirm-deactivate').disabled=pending;el('cancel-deactivate').disabled=pending;
 }
 function clearPrivate(text){
  generation++;readSerial++;confirmed=null;target=null;pending=false;
  el('private-account').hidden=true;el('mac-list').replaceChildren();el('slot-count').textContent='';el('licence-status').textContent='';el('licence-end').textContent='';el('reauth-message').textContent='';
  el('deactivate-confirmation').close();message(text);controls();
 }
 function render(state){
  confirmed=state;el('private-account').hidden=false;el('licence-status').textContent=state.licence.state.charAt(0).toUpperCase()+state.licence.state.slice(1);
  el('licence-end').textContent=state.licence.endsAt===null?'':'Until '+new Date(state.licence.endsAt*1000).toLocaleString();
  el('reauth-message').textContent=state.reauthRequired?'Reauthentication required before starting a trial or deactivating a Mac.':'';
  el('slot-count').textContent=state.slots.used+' of '+state.slots.limit+' Mac slots used';
  const nodes=state.slots.macs.map(mac=>{
   const item=document.createElement('li');item.dataset.activationId=mac.activationID;
   const name=document.createElement('span');name.textContent=label(mac);item.append(name);
   const button=document.createElement('button');button.type='button';button.textContent='Deactivate';button.addEventListener('click',()=>{
    if(pending||confirmed!==state||state.reauthRequired)return;
    target={activationID:mac.activationID,activationRevision:mac.activationRevision,accountRevision:state.accountRevision,label:label(mac),csrfToken:state.csrfToken};
    el('deactivate-target').textContent=target.label;el('deactivate-confirmation').showModal();
   });item.append(button);return item;
  });el('mac-list').replaceChildren(...nodes);message('Account confirmed.');error('');controls();
 }
 async function refresh(){
  const current=generation,serial=++readSerial;el('refresh-account').disabled=true;
  try{
   const response=await fetch(root+'/state',{credentials:'same-origin',cache:'no-store',redirect:'error'});
   if(current!==generation||serial!==readSerial)return;
   if(response.status===401){clearPrivate('Your session has expired. Sign in again.');return;}
   if(!response.ok)throw Error('state');
   const state=await response.json();if(current!==generation||serial!==readSerial)return;
   if(state.outcome!=='account')throw Error('state');render(state);
  }catch{if(current===generation&&serial===readSerial)error('Account verification is unavailable. The last confirmed account is shown. Refresh to check again.');}
  finally{if(current===generation&&serial===readSerial)el('refresh-account').disabled=false;else if(!confirmed)el('refresh-account').disabled=false;}
 }
 function requestID(){const bytes=crypto.getRandomValues(new Uint8Array(16));return Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');}
 async function mutate(path,body,csrfToken){
  if(pending||!confirmed)return;
  pending=true;generation++;readSerial++;const current=generation;controls();error('');message('Waiting for service confirmation…');
  try{
   const response=await fetch(root+path,{method:'POST',credentials:'same-origin',redirect:'error',headers:{'Content-Type':'application/json','X-CSRF-Token':csrfToken},body:JSON.stringify(body)});
   const result=await response.json();if(current!==generation)return;
   if(!response.ok){
    if(response.status===401&&result.outcome==='reauthRequired'){error('Reauthentication required before this change.');message('No change confirmed.');return;}
    if(response.status===401){clearPrivate('Your session has expired. Sign in again.');return;}
    error('The change was not confirmed. Refresh your account before trying again.');message('No change confirmed.');return;
   }
   if(path==='/logout'){clearPrivate('Signed out. Sign in again to view your account.');return;}
   el('deactivate-confirmation').close();target=null;message('Change confirmed. Checking the current account…');
   // Keep the last confirmed list until a fresh state response has arrived.
   await refresh();
  }catch{if(current===generation){error('The result is uncertain. Refresh your account before trying again.');message('No change confirmed.');}}
  finally{if(current===generation){pending=false;controls();}}
 }
 el('refresh-account').addEventListener('click',refresh);
 el('start-trial').addEventListener('click',()=>{if(!confirmed||pending||confirmed.reauthRequired||!confirmed.licence.trialAvailable)return;mutate('/trial',{expectedAccountRevision:confirmed.accountRevision,requestID:requestID()},confirmed.csrfToken);});
 el('logout-account').addEventListener('click',()=>{if(confirmed)mutate('/logout',{},confirmed.csrfToken);});
 el('cancel-deactivate').addEventListener('click',()=>{if(!pending){target=null;el('deactivate-confirmation').close();}});
 el('deactivate-confirmation').addEventListener('cancel',event=>{if(pending)event.preventDefault();else target=null;});
 el('confirm-deactivate').addEventListener('click',()=>{if(!target||pending)return;const selected=target;mutate('/macs/'+selected.activationID+'/deactivate',{expectedAccountRevision:selected.accountRevision,expectedActivationRevision:selected.activationRevision,requestID:requestID()},selected.csrfToken);});
 refresh();
})();
