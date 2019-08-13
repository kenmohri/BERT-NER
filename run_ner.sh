#!/usr/bin/env bash

  python BERT_NER_jp.py\
    --task_name="NER"  \
    --do_lower_case=False \
    --crf=True \
    --do_train=True   \
    --do_eval=True   \
    --do_predict=True \
    --data_dir=data/IBOdata_sentencePiece   \
    --model_file=bert_model.v0008/spm/spm4bert.model \
    --vocab_file=bert_model.v0008/spm/spm4bert.vocab  \
    --bert_config_file=bert_model.v0008/bert_config.json \
    --init_checkpoint=bert_model.v0008/model.ckpt-1000000   \
    --max_seq_length=128   \
    --train_batch_size=32   \
    --learning_rate=2e-5   \
    --num_train_epochs=4.0   \
    --output_dir=./output/result_dir


#perl conlleval.pl -d '\t' < ./output/result_dir/label_test.txt
