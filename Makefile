

all:


ifeq  ($(shell uname),Linux)
    _SETUP_BASE:=sudo apt-get -y install cmake pkg-config libgoogle-perftools-dev
    _SETUP_LAST:= && sudo ldconfig -v
else
    _SETUP_BASE:=brew install protobuf autoconf automake libtool
endif


SPM_SRC:=./local/src/sentencepiece
spm-setup:
	$(_SETUP_BASE) \
	&& pip3 install sentencepiece \
	&& git clone git@github.com:google/sentencepiece.git $(SPM_SRC) \
	&& cd $(SPM_SRC) \
	&& mkdir build \
	&& cd build \
	&& cmake .. \
	&& make -j $(shell nproc) \
	&& sudo make install \
	$(_SETUP_LAST)



#To be designated
CAT:=zcat
IN_DIR :=/please/designate_input
IN_DIR_ := $(IN_DIR:/=)
OUT_DIR :=/please/designate_output
OUT_DIR_SPM :=$(OUT_DIR)/spm
SPM_MODEL_NAME:=spm4bert
OUT_SPM_PREFIX:=$(OUT_DIR_SPM)/$(SPM_MODEL_NAME)
OUT_SPM_MODEL:=$(OUT_SPM_PREFIX).model
OUT_SPM_VOCAB:=$(OUT_SPM_PREFIX).vocab
SPM_CORPUS :=$(OUT_DIR)/sent.spm.txt
SPM_VOCAB_SIZE :=$(shell cat $(OUT_SPM_VOCAB) | wc -l)
SPM_TRAIN_BIN:=spm_train
SPM_TRAIN_OPT:=--input_sentence_size 3000000 --shuffle_input_sentence=true


$(SPM_CORPUS): $(IN_DIR_)
	mkdir -p $(OUT_DIR_SPM)
	find $(IN_DIR_) -type f | grep -v err | sort | xargs $(CAT) | grep -v '^#' > $@.tmp \
	    && mv $@.tmp $@
spm-corpus: $(SPM_CORPUS)

$(OUT_SPM_MODEL): $(SPM_CORPUS)
	mkdir -p $(OUT_DIR_SPM)
	$(SPM_TRAIN_BIN) -vocab_size $(SPM_VOCAB_SIZE) \
		--model_type unigram \
		--model_prefix $(OUT_SPM_PREFIX) \
		--input $< \
	   	--num_threads $(shell nproc) \
	 	--control_symbols='[PAD],[CLS],[SEP],[MASK]' \
		$(SPM_TRAIN_OPT)
	if [ ! -f $@ ];then exit 1; fi
	if [ ! -f $(OUT_SPM_VOCAB) ];then exit 1; fi

spm-train: $(OUT_SPM_MODEL)


BERT_SRC:=./local/src/bert
bert-setup: bert.patch
	git clone git@github.com:google-research/bert.git $(BERT_SRC) \
	&& patch -d $(BERT_SRC) < $<
bert-repatch:
	cd $(BERT_SRC) \
	&& git reset --hard \
	&& patch -p1 < ../../../bert.patch


OUT_BERTDATA_DIR0:=$(OUT_DIR)/bert_input0
OUT_BERTDATA_PREFIX:=$(OUT_BERTDATA_DIR0)/data-
OUT_BERTDATA_DIR1:=$(OUT_DIR)/bert_input1
BERT_MAX_SEQ_LENGTH:=128
BERT_MAX_PREDICTIONS_PER_SEQ:=20
BERT_MASKED_LM_PROB:=0.15
BERT_DUPE_FACTOR:=10
BERT_MAXDOC_PERFILE:=50000
BERT_DO_LOWER_CASE=False
BERT_RANDOM_SEED=12345
bert-data0:
	mkdir -p $(dir $(OUT_BERTDATA_PREFIX))
	find $(IN_DIR_) -type f | grep -v err | sort | xargs $(CAT) \
	    | python3 ./sentconv4bert.py -i - -o $(OUT_BERTDATA_PREFIX) -m $(BERT_MAXDOC_PERFILE)

BERT_DATA0_FILES:=$(shell find $(OUT_BERTDATA_DIR0) -type f | sort -n)
BERT_DATA1_FILES := $(patsubst $(OUT_BERTDATA_DIR0)/%, $(OUT_BERTDATA_DIR1)/%.tfrecord, $(BERT_DATA0_FILES))
$(OUT_BERTDATA_DIR1)/%.tfrecord: $(OUT_BERTDATA_DIR0)/%
	mkdir -p $(OUT_BERTDATA_DIR1)
	      python3 $(BERT_SRC)/create_pretraining_data.py \
	        --input_file=$< \
	        --output_file=$@ \
	        --vocab_file=$(OUT_SPM_VOCAB) \
	        --model_file=$(OUT_SPM_MODEL) \
	        --do_lower_case=$(BERT_DO_LOWER_CASE) \
	        --max_seq_length=$(BERT_MAX_SEQ_LENGTH) \
	        --max_predictions_per_seq=$(BERT_MAX_PREDICTIONS_PER_SEQ) \
	        --masked_lm_prob=$(BERT_MASKED_LM_PROB) \
	        --random_seed=$(BERT_RANDOM_SEED) \
	        --dupe_factor=$(BERT_DUPE_FACTOR)
bert-data1: $(BERT_DATA1_FILES)


BERT_STEP_NUM:=1000000
BERT_TRAIN_BATCH_SIZE:=32
BERT_NUM_WARMUP_STEPS:=10000
BERT_LEARNING_RATE:=5e-5
BERT_NUM_ATTENTION_HEADS=12
BERT_NUM_HIDDEN_LAYERS=12

BERT_OPTS:=
BERT_CONFIG_ORIGINAL:=bert_config.template.json
OUT_BERTMODEL_DIR:=$(OUT_DIR)/bert_model
bert-train:
	if echo '$(OUT_BERTMODEL_DIR)' | grep -q '^gs://' ; then\
	    sed 's/#vocab_size#/$(SPM_VOCAB_SIZE)/' $(BERT_CONFIG_ORIGINAL) \
	       | sed 's/#num_attention_heads#/$(BERT_NUM_ATTENTION_HEADS)/' \
	       | sed 's/#num_hidden_layers#/$(BERT_NUM_HIDDEN_LAYERS)/' \
	       | gsutil cp -L bert_config.tmp.json - $(OUT_BERTMODEL_DIR)/bert_config.json ;\
	       rm bert_config.tmp.json ;\
	else\
	    mkdir -p $(OUT_BERTMODEL_DIR) ;\
	    sed 's/#vocab_size#/$(SPM_VOCAB_SIZE)/' $(BERT_CONFIG_ORIGINAL) \
	       | sed 's/#num_attention_heads#/$(BERT_NUM_ATTENTION_HEADS)/' \
	       | sed 's/#num_hidden_layers#/$(BERT_NUM_HIDDEN_LAYERS)/' \
	       > $(OUT_BERTMODEL_DIR)/bert_config.json ;\
	fi
	python3 $(BERT_SRC)/run_pretraining.py \
	  --input_file="$(OUT_BERTDATA_DIR1)/*.tfrecord" \
	  --output_dir=$(OUT_BERTMODEL_DIR) \
	  --do_train=True \
	  --do_eval=True \
	  --bert_config_file=$(OUT_BERTMODEL_DIR)/bert_config.json \
	  --train_batch_size=$(BERT_TRAIN_BATCH_SIZE) \
	  --max_seq_length=$(BERT_MAX_SEQ_LENGTH) \
	  --max_predictions_per_seq=20 \
	  --num_train_steps=$(BERT_STEP_NUM) \
	  --num_warmup_steps=$(BERT_NUM_WARMUP_STEPS) \
	  --learning_rate=$(BERT_LEARNING_RATE) \
	  $(BERT_OPTS)

OUT_BERTMODEL_DIST_DIR_NAME:=bert_model_dist
OUT_BERTMODEL_DIST_DIR:=$(OUT_DIR)/$(OUT_BERTMODEL_DIST_DIR_NAME)
OUT_BERTMODEL_DIST_ZIP_NAME:=$(OUT_BERTMODEL_DIST_DIR_NAME).zip
bert-zip:
	rm -rf  $(OUT_BERTMODEL_DIST_DIR)
	mkdir -p $(OUT_BERTMODEL_DIST_DIR)
	echo $$MAXSTEP ; \
	if echo "$(OUT_BERTMODEL_DIR)" | grep "^gs://" ; then\
	    gsutil cp $(OUT_BERTMODEL_DIR)/checkpoint $(OUT_BERTMODEL_DIST_DIR); \
	    MAXSTEP=`grep ^model_checkpoint_path $(OUT_BERTMODEL_DIST_DIR)/checkpoint | grep -o '[0-9]*' ` && gsutil cp $(OUT_BERTMODEL_DIR)/model.ckpt-$$MAXSTEP.* $(OUT_BERTMODEL_DIST_DIR); \
	    gsutil cp -r $(OUT_BERTMODEL_DIR)/eval $(OUT_BERTMODEL_DIST_DIR); \
	    gsutil cp $(OUT_BERTMODEL_DIR)/graph.pbtxt $(OUT_BERTMODEL_DIST_DIR); \
	    gsutil cp $(OUT_BERTMODEL_DIR)/checkpoint $(OUT_BERTMODEL_DIST_DIR); \
	    gsutil cp $(OUT_BERTMODEL_DIR)/bert_config.json $(OUT_BERTMODEL_DIST_DIR); \
	    gsutil cp $(OUT_BERTMODEL_DIR)/eval_results.txt $(OUT_BERTMODEL_DIST_DIR); \
	else \
	    MAXSTEP=`grep ^model_checkpoint_path $(OUT_BERTMODEL_DIR)/checkpoint | grep -o '[0-9]*' ` &&\
	    ln -s `realpath $(OUT_BERTMODEL_DIR)`/model.ckpt-$$MAXSTEP.* $(OUT_BERTMODEL_DIST_DIR); \
	    ln -s `realpath $(OUT_BERTMODEL_DIR)`/eval $(OUT_BERTMODEL_DIST_DIR); \
	    ln -s `realpath $(OUT_BERTMODEL_DIR)`/graph.pbtxt $(OUT_BERTMODEL_DIST_DIR); \
	    ln -s `realpath $(OUT_BERTMODEL_DIR)`/checkpoint $(OUT_BERTMODEL_DIST_DIR); \
	    cp `realpath $(OUT_BERTMODEL_DIR)`/bert_config.json $(OUT_BERTMODEL_DIST_DIR); \
	    ln -s `realpath $(OUT_BERTMODEL_DIR)`/eval_results.txt $(OUT_BERTMODEL_DIST_DIR); \
	fi; \
	ln -s `realpath $(OUT_DIR_SPM)` $(OUT_BERTMODEL_DIST_DIR); \
	ln -s `realpath bert.patch` $(OUT_BERTMODEL_DIST_DIR); \
	cd $(OUT_DIR) && zip -r $(OUT_BERTMODEL_DIST_ZIP_NAME) $(OUT_BERTMODEL_DIST_DIR_NAME); \



lint:

test:

.PHONY: all spm-setup lint test

.DELETE_ON_ERROR:
