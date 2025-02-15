import React from 'react';
import type { FunctionDescription } from '@openfn/describe-package';
import { marked } from 'marked';

type RenderFunctionProps = {
  fn: FunctionDescription;
  onInsert?: (text: string) => void;
}

type PreButtonFunctionProps = {
  tooltip?: string;
  label: string;
  onClick?: () => void;
}

const doCopy = async (text: string) => {
  const type = "text/plain";
  const data = [new ClipboardItem({ [type]: new Blob([text], { type } )})];

  try {
    await navigator.clipboard.write(data);
  } catch(e) {
    alert('COPY FAILED')
  }
}

const getSignature = (fn: FunctionDescription) => {
  const paramList: string[] = fn.parameters.map(({ name }) => name);

  return `${fn.name}(${paramList.join(', ')})`
}

const PreButton = ({ label, onClick, tooltip }: PreButtonFunctionProps) => 
  // TODO give some kind of feedback on click
  <button
    className="rounded-md bg-slate-300 text-white px-2 py-1 mr-1 text-xs"
    title={tooltip || ''}
    onClick={onClick}>
    {label}
  </button>

type ExampleProps = {
  // TODO the string format is already deprecated
  eg: string |  { code: string, caption?: string };
  onInsert?: (text: string) => void;
}

const Example = ({ eg, onInsert }: ExampleProps) => {
  let code = '';
  let caption;
  if (typeof eg === 'string') {
    code = eg;
  } else {
    code = eg.code;
    caption = eg.caption;
  }
  return (
    <section>
      <label className="block text-sm text-secondary-700 mt-2">
        Example{ caption && `: ${caption}`}
      </label>
      <div style={{ marginTop: '-6px'}}>
        <div className="w-full px-5 text-right" style={{ height: '13px'}}>
          <PreButton label="COPY" onClick={() => doCopy(code)} tooltip="Copy this example to the clipboard"/>
          {onInsert && <PreButton label="ADD" onClick={() => onInsert(code)} tooltip="Add this snippet to the end of the code"/>}
        </div>
        <pre
          className="rounded-md pl-4 pr-30 py-2 mx-4 my-0 font-mono bg-slate-100 border-2 border-slate-200 text-slate-800 min-h-full text-xs overflow-x-auto"
          >
            {code}
        </pre>
      </div>
      </section>
  )
}

const RenderFunction = ({ fn, onInsert }: RenderFunctionProps) => {
  return (
    <details>
      <summary className="text-m text-secondary-700 mb-1 cursor-pointer marker:text-slate-600 marker:text-sm">
        <span className="relative top-px">{getSignature(fn)}</span>
      </summary>
      <div className="block mb-4 pl-4">
        <p className="block text-sm" dangerouslySetInnerHTML={{ __html: marked.parse(fn.description)}}></p>
        {fn.examples.map((eg, idx) =>
          <Example eg={eg} onInsert={onInsert} key={`${fn.name}-eg-${idx}`} />
        )}
        </div>
    </details>
  )
}

export default RenderFunction;