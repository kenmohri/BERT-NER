
# BERT with  SentencePiece

## Install SentencePiece and patched BERT

```sh
make spm-setup
make bert-setup
```

To re-patch to BERT,  execute ``make bert-repatch``.


## Pre-training

```sh
# Training of SentencePiece
make spm-corpus IN_DIR=./test/texts OUT_DIR=./test.out
make spm-train IN_DIR=./test/texts OUT_DIR=./test.out SPM_VOCAB_SIZE=1000

# Data generation
make bert-data0 IN_DIR=./test/texts OUT_DIR=./test.out
make -j `nproc` bert-data1 OUT_DIR=./test.out

# Training
make bert-train OUT_DIR=./test.out BERT_STEP_NUM=10

# Zip-model
make bert-zip OUT_DIR=./test.out OUT_BERTMODEL_DIST_DIR_NAME=bert_model.v0000
```




## Example of pre-training with TPU

```
where pgrep # check wheter the command exists

gcloud compute tpus create my-tpu-0 --network=default --range=10.240.1.0 --version=1.12 --zone asia-east1-c
# If already exists
#  gcloud compute tpus start my-tpu-0 --zone asia-east1-c


vi ~/data/my_corpus/version0/do.sh
# Write like this
cd ~/workspace/bert-spm
make bert-train OUT_BERTDATA_DIR1='gs://rcl-megagon-aiassistant-shared/my_corpus/version0/bert_input1' \
    OUT_BERTMODEL_DIR='gs://rcl-megagon-aiassistant-shared/my_corpus/version0/out.bert' \
    BERT_STEP_NUM=1000000 \
    OUT_SPM_VOCAB=~/data/my_corpus/version0/spm/spm4bert.vocab \
    BERT_TRAIN_BATCH_SIZE=512 \
    BERT_OPTS='--use_tpu=True --tpu_name=my-tpu-0 --tpu_zone=asia-east1-c --save_checkpoints_steps=2000' \
    2>&1 | tee -a ~/data/my_corpus/version0/log.txt
zsh ~/data/my_corpus/version0/do.sh

# In other shell for TPU reboot
tail -n0 -F ~/data/my_corpus/version0/log.txt \
 | grep --line-buffered 'This may be due to a preemption in a connected worker' \
 | xargs -l bash -c 'slack_notify "TPU reboot"; sleep 60; kill -9 $(pgrep -af "make.*.version0") ; killall -9 $(pgrep -af "tee.*.version0") ; sleep 120; zsh ~/data/my_corpus/version0/log.txt'

# In other shell to finalize
cd ~/workspace/bert-spm
tail -n0 -F ~/data/my_corpus/version0/log.txt \
  | grep --line-buffered 'global_step = 1000000' | head -n1; \
  slack_notify 'bert done';
  gcloud compute tpus stop my-tpu-0 --zone asia-east1-c;\
  make bert-zip OUT_DIR=~/data/my_corpus/version0 \
    OUT_BERTMODEL_DIR='gs://rcl-megagon-aiassistant-shared/my_corpus/version0/out.bert' \
    OUT_SPM_VOCAB=~/data/my_corpus/version0/spm/spm4bert.vocab \
    OUT_BERTMODEL_DIST_DIR_NAME=bert_model.version0 ;\
  gsutil cp ~/data/my_corpus/version0/bert_model.version0.zip \
    gs://rcl-megagon-aiassistant-shared/my_corpus/bert;
  sudo shutdown -h now
```


# References
- [BERT with SentencePiece で日本語専用の pre-trained モデルを学習し、それを基にタスクを解く](https://techlife.cookpad.com/entry/2018/12/04/093000)
- [BERT with SentencePiece を日本語 Wikipedia で学習してモデルを公開しました](https://yoheikikuta.github.io/bert-japanese/)
    - [Model trained with Japanese Wikipedia](https://github.com/yoheikikuta/bert-japanese)

