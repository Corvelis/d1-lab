"""Compare quantized GGUF inference with Liquid's PyTorch encoder/head using the same dequantized weights.

Usage: PYTHONPATH=../third_party/llama.cpp/gguf-py python reference_parity.py
       --reference-dir /path/containing/encoder.py/and/config.json --model model.gguf --cli ../build-macos/d1-cli
The reference files are deliberately supplied by the caller; this test does not execute downloaded code implicitly.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import numpy as np
import torch
from gguf import GGUFReader
from gguf.quants import dequantize

p=argparse.ArgumentParser()
p.add_argument('--reference-dir', type=Path, required=True)
p.add_argument('--model', required=True)
p.add_argument('--cli', required=True)
p.add_argument('--backend', default='cpu', choices=['cpu','metal'])
p.add_argument('--tolerance', type=float, default=0.2)
p.add_argument('--media-report', type=Path)
p.add_argument('--reference-prefix-dir', type=Path)
args=p.parse_args()
torch.set_num_threads(4)
spec=importlib.util.spec_from_file_location('liquid_reference_encoder',args.reference_dir/'encoder.py')
encoder=importlib.util.module_from_spec(spec); spec.loader.exec_module(encoder)
cfg=json.loads((args.reference_dir/'config.json').read_text())
reader=GGUFReader(args.model)
tensors={t.name:t for t in reader.tensors}
with torch.device('meta'):
    trunk=encoder.Trunk(cfg['text_config'])
    head=encoder.DecisionHead(cfg['text_config']['hidden_size'],cfg['head_layers'])

def assign(module, target, source):
    owner=module
    for name in target.split('.')[:-1]: owner=getattr(owner,name)
    name=target.split('.')[-1]
    parameter=getattr(owner,name)
    tensor=tensors[source]
    values=dequantize(tensor.data,tensor.tensor_type).reshape(tuple(parameter.shape)).copy()
    setattr(owner,name,torch.nn.Parameter(torch.from_numpy(values.astype(np.float32)),requires_grad=False))

assign(trunk,'embed_tokens.weight','token_embd.weight')
assign(trunk,'embedding_norm.weight','token_embd_norm.weight')
for i,layer in enumerate(trunk.layers):
    base=f'blk.{i}.'
    for dst,src in [('operator_norm.weight','attn_norm.weight'),('ffn_norm.weight','ffn_norm.weight'),('feed_forward.w1.weight','ffn_gate.weight'),('feed_forward.w2.weight','ffn_down.weight'),('feed_forward.w3.weight','ffn_up.weight')]: assign(layer,dst,base+src)
    if layer.is_attention_layer:
        for dst,src in [('q_proj','attn_q'),('k_proj','attn_k'),('v_proj','attn_v'),('out_proj','attn_output'),('q_layernorm','attn_q_norm'),('k_layernorm','attn_k_norm')]: assign(layer,'self_attn.'+dst+'.weight',base+src+'.weight')
    else:
        for dst,src in [('conv.conv','shortconv.conv'),('conv.in_proj','shortconv.in_proj'),('conv.out_proj','shortconv.out_proj')]: assign(layer,dst+'.weight',base+src+'.weight')
assign(head,'type_emb.weight','token_types.weight')
for i,layer in enumerate(head.head.layers):
    for dst,src in [('self_attn.in_proj','attn_qkv'),('self_attn.out_proj','attn_output'),('linear1','ffn_up'),('linear2','ffn_down'),('norm1','attn_norm'),('norm2','ffn_norm')]:
        for suffix in ['weight','bias']:
            target=dst+'_'+suffix if dst=='self_attn.in_proj' else dst+'.'+suffix
            assign(layer,target,f'blk.{i+len(trunk.layers)}.{src}.{suffix}')
for dst,src in [('scorer.0','cls.norm'),('scorer.1','cls'),('scorer.3','cls.output')]:
    for suffix in ['weight','bias']: assign(head,dst+'.'+suffix,src+'.'+suffix)
trunk.eval(); head.eval()

questions=[
    {'type':'choice','instructions':'Choose the department for this request.','options':[{'name':'Shipping','description':'Delivery and tracking'},{'name':'Returns','description':'Damage and replacement'},{'name':'Billing','description':'Payments'},{'name':'Other','description':'None of the above'}]},
    {'type':'noul','instructions':'Does the customer request a replacement?'},
    {'type':'score','instructions':'Rate how damaged the package is.','levels':['No damage','Damaged']},
]
request={'state':'The package arrived damaged. Can I get a replacement?','questions':questions}
env=dict(os.environ,D1_DEBUG_TOKENS='1')
run=subprocess.run([args.cli,args.model,args.backend],input=json.dumps(request)+'\n',text=True,encoding='utf-8',errors='replace',capture_output=True,env=env,check=True)
rows=[json.loads(line) for line in run.stdout.splitlines()]
assert len(rows)==2 and 'error' not in rows[-1],rows
checks=[]
with torch.no_grad():
    for question,result in zip(questions,rows[-1]['results']):
        ids=torch.tensor([result['debugTokenIds']]); markers=torch.tensor([result['debugMarkers']])
        pad=torch.ones_like(ids,dtype=torch.bool)
        hidden=trunk(trunk.embed_tokens(ids),pad,torch.tensor([0]))
        type_id={'choice':0,'score':1,'noul':2}[question['type']]
        expected=head(hidden,pad,markers,torch.ones_like(markers,dtype=torch.bool),torch.tensor([type_id]))[0].numpy()
        actual=np.array([v['logit'] for v in result['probabilities']])
        delta=float(np.abs(expected-actual).max())
        assert delta<args.tolerance,(question['type'],expected,actual,delta)
        assert int(expected.argmax())==int(actual.argmax())
        checks.append({'type':question['type'],'referenceLogits':expected.tolist(),'nativeLogits':actual.tolist(),'maxAbsoluteError':delta})
if args.media_report:
    with torch.no_grad():
        for line in args.media_report.read_text().splitlines()[1:]:
            native=json.loads(line)
            prefix_values=np.load(args.reference_prefix_dir/(Path(native['debugPrefixFile']).stem+'.npy')) if args.reference_prefix_dir else np.fromfile(native['debugPrefixFile'],dtype=np.float32)
            prefix=torch.from_numpy(prefix_values.reshape(1,-1,cfg['text_config']['hidden_size']))
            offset=prefix.shape[1]
            for result in native['results']:
                ids=torch.tensor([result['debugTokenIds']]); markers=torch.tensor([result['debugMarkers']])
                embeddings=torch.cat([prefix,trunk.embed_tokens(ids)],dim=1)
                pad=torch.ones(embeddings.shape[:2],dtype=torch.bool)
                hidden=trunk(embeddings,pad,torch.tensor([offset]))[:,offset:]
                type_id={'choice':0,'score':1,'noul':2}[result['type']]
                expected=head(hidden,torch.ones_like(ids,dtype=torch.bool),markers,torch.ones_like(markers,dtype=torch.bool),torch.tensor([type_id]))[0].numpy()
                actual=np.array([v['logit'] for v in result['probabilities']])
                delta=float(np.abs(expected-actual).max())
                assert delta<args.tolerance,(native['debugPrefixFile'],expected,actual,delta)
                checks.append({'type':Path(native['debugPrefixFile']).stem,'prefixTokens':offset,'referenceLogits':expected.tolist(),'nativeLogits':actual.tolist(),'maxAbsoluteError':delta})
print(json.dumps({'backend':args.backend,'tolerance':args.tolerance,'checks':checks},indent=2))
