"""Check both d1-omni media towers against Liquid's caller-supplied PyTorch code.
Use the same Q8_0 GGUF dequantized weights; no original model download is needed.
Requires torch, gguf, numpy, Pillow, torchvision and transformers >=4.51 (SigLIP2).
The native reports must be produced with D1_DEBUG_PREFIX_DIR set.
"""
import argparse
import importlib.util,json,wave
from pathlib import Path
import numpy as np
import torch
from gguf import GGUFReader
from gguf.quants import dequantize
from transformers import Siglip2VisionConfig,Siglip2VisionModel
from PIL import Image
p=argparse.ArgumentParser()
p.add_argument('--reference-dir',type=Path,required=True)
p.add_argument('--projector',required=True)
p.add_argument('--image',type=Path,required=True,help='256x256 RGB fixture (no position resizing)')
p.add_argument('--audio',type=Path,required=True,help='Mono 16 kHz int16 WAV fixture')
p.add_argument('--native-report',type=Path,required=True,help='JSONL containing native image and audio results')
p.add_argument('--output-dir',type=Path,required=True)
args=p.parse_args()
args.output_dir.mkdir(parents=True,exist_ok=True)
torch.set_num_threads(4)
cfg=json.loads((args.reference_dir/'config.json').read_text())
ts={t.name:t for t in GGUFReader(args.projector).tensors}
reports={Path(row['debugPrefixFile']).stem:row for line in args.native_report.read_text().splitlines() if 'debugPrefixFile' in (row:=json.loads(line))}
checks=[]
def module(name):
 s=importlib.util.spec_from_file_location(name,args.reference_dir/(name+'.py'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
vision=module('vision'); audio=module('audio')
def assign(m,target,source):
 o=m
 for n in target.split('.')[:-1]:o=getattr(o,n)
 n=target.split('.')[-1];p=getattr(o,n);t=ts[source];a=dequantize(t.data,t.tensor_type).reshape(p.shape).copy();
 if source=='v.patch_embd.weight':a=a.reshape(768,3,16,16).transpose(0,2,3,1).reshape(p.shape)
 setattr(o,n,torch.nn.Parameter(torch.from_numpy(a.astype(np.float32)),requires_grad=False))
with torch.device('meta'):v=vision.Vision(cfg['vision_config'],cfg['projector_hidden_size'],cfg['text_config']['hidden_size'])
for d,s in [('embeddings.patch_embedding','v.patch_embd'),('embeddings.position_embedding','v.position_embd'),('post_layernorm','v.post_ln')]:
 for suffix in ['weight','bias']:
  if s+'.'+suffix in ts:assign(v.tower,'vision_model.'+d+'.'+suffix,s+'.'+suffix)
for i in range(12):
 for d,s in [('layer_norm1','ln1'),('layer_norm2','ln2'),('mlp.fc1','ffn_up'),('mlp.fc2','ffn_down'),('self_attn.q_proj','attn_q'),('self_attn.k_proj','attn_k'),('self_attn.v_proj','attn_v'),('self_attn.out_proj','attn_out')]:
  for suffix in ['weight','bias']:assign(v.tower,f'vision_model.encoder.layers.{i}.{d}.{suffix}',f'v.blk.{i}.{s}.{suffix}')
for d,s in [('linear_1','mm.1'),('linear_2','mm.2')]:
 for suf in ['weight','bias']:assign(v.projector,d+'.'+suf,s+'.'+suf)
v.eval()
# SigLIP's pooling head is unused; meta weights there are intentionally left unloaded.
with torch.no_grad():
 x=v([Image.open(args.image)]).numpy()[0]
n=np.fromfile(reports['image-prefix']['debugPrefixFile'],dtype=np.float32).reshape(-1,1024)
assert x.shape==n.shape
relative_rms=float(np.square(x-n).mean()**.5/np.square(x).mean()**.5)
assert relative_rms<0.01,relative_rms
checks.append({'type':'image','prefixTokens':len(x),'maxAbsoluteError':float(np.abs(x-n).max()),'relativeRMSError':relative_rms})
np.save(args.output_dir/'image-prefix.npy',x)
with torch.device('meta'):a=audio.Audio(cfg['audio_config'],1024)
for i in [0,2,3,5,6]:
 for suf in ['weight','bias']:assign(a,f'encoder.pre_encode.conv.{i}.{suf}',f'a.conv1d.{i}.{suf}')
for suf in ['weight','bias']:assign(a,'encoder.pre_encode.out.'+suf,'a.pre_encode.out.'+suf)
for i in range(17):
 for d,s in [('norm_feed_forward1','ffn_norm'),('feed_forward1.linear1','ffn_up'),('feed_forward1.linear2','ffn_down'),('norm_self_att','ln1'),('norm_conv','norm_conv'),('norm_feed_forward2','ffn_norm_1'),('feed_forward2.linear1','ffn_up_1'),('feed_forward2.linear2','ffn_down_1'),('norm_out','ln2'),('self_attn.linear_q','attn_q'),('self_attn.linear_k','attn_k'),('self_attn.linear_v','attn_v'),('self_attn.linear_out','attn_out'),('self_attn.linear_pos','linear_pos'),('conv.pointwise_conv1','conv_pw1'),('conv.pointwise_conv2','conv_pw2'),('conv.depthwise_conv','conv_dw'),('conv.batch_norm','conv_norm')]:
  for suf in ['weight','bias']:
   if f'a.blk.{i}.{s}.{suf}' in ts:assign(a,f'encoder.layers.{i}.{d}.{suf}',f'a.blk.{i}.{s}.{suf}')
 for suf in ['u','v']:assign(a,f'encoder.layers.{i}.self_attn.pos_bias_{suf}',f'a.blk.{i}.pos_bias_{suf}')
 bn=a.encoder.layers[i].conv.batch_norm
 bn.running_mean=torch.zeros(512);bn.running_var=torch.ones(512)*(1-bn.eps);bn.num_batches_tracked=torch.tensor(0)
for d,s in [('adapter.norm','mm.a.mlp.0'),('adapter.linear_1','mm.a.mlp.1'),('adapter.linear_2','mm.a.mlp.3'),('residual.ln','mm.a.mlp.4'),('residual.down','mm.a.mlp.5'),('residual.up','mm.a.mlp.6')]:
 for suf in ['weight','bias']:assign(a,d+'.'+suf,s+'.'+suf)
a.eval()
f=wave.open(str(args.audio));assert f.getframerate()==16000 and f.getnchannels()==1 and f.getsampwidth()==2;w=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').copy();f.close()
with torch.no_grad():x=a(w).numpy()[0]
n=np.fromfile(reports['audio-prefix']['debugPrefixFile'],dtype=np.float32).reshape(-1,1024)
assert x.shape==n.shape
assert float(np.abs(x-n).max())<0.02
checks.append({'type':'audio','prefixTokens':len(x),'maxAbsoluteError':float(np.abs(x-n).max()),'relativeRMSError':float(np.square(x-n).mean()**.5/np.square(x).mean()**.5)})
np.save(args.output_dir/'audio-prefix.npy',x)
print(json.dumps({'checks':checks},indent=2))
