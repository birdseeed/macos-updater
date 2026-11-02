// Pure resource classification only; caller metrics create no SQL, plan or authority.
// This classifier grants no database or mutation authority.
export function checkLifecycleBudget(_input:unknown):{outcome:'within'|'exceeded'|'invalid'}{try {
  if(!_input || typeof _input!=='object' || Array.isArray(_input) || Object.getPrototypeOf(_input)!==Object.prototype)return {outcome:'invalid'};
  const keys=['effectRows','statementCount','maxBindings'];
  if(Reflect.ownKeys(_input).length!==3)return {outcome:'invalid'};
  const values=keys.map(key=>Object.getOwnPropertyDescriptor(_input,key));
  if(values.some(d=>!d || !Object.hasOwn(d,'value') || typeof d.value!=='number' || !Number.isSafeInteger(d.value) || d.value<0))return {outcome:'invalid'};
  return {outcome:values[0]!.value<=364&&values[1]!.value<=1024&&values[2]!.value<=100?'within':'exceeded'};
 }catch{return {outcome:'invalid'};}}
