<script setup>
import { LoadingOutlined, QuestionCircleOutlined } from '@ant-design/icons-vue'
import { useNodeStore } from '@/stores/nodes'
import { onMounted, computed, h } from 'vue'
import axios from 'axios'

const props = defineProps({
  node: String
})

const store = useNodeStore()
const state = computed(() => store.node[props.node])

const mempoolTableCols = [
  {
    title: 'Transaction ID',
    dataIndex: 'txid',
    key: 'txid'
  }
]

const utxosTableCols = [
  {
    title: 'Address',
    dataIndex: 'address',
    key: 'address'
  },
  {
    title: 'Balance',
    dataIndex: 'balance',
    key: 'balance',
    width: 10,
    align: 'right'
  }
]
</script>

<template lang="pug">
.mining-power
  p.pb-2.opacity-50(style='font-weight: 420') Mining Power
    a-tooltip(placement='right')
      template(#title)
        span Percentage of blocks this node has mined (used for selecting next validators)
      question-circle-outlined.ml-1(style='font-size: 14px; bottom: 1px')
  a-progress(type='circle', :stroke-color='{ "0%": "#1DA57A", "100%": "#6c52eb" }', :percent='+state.mining_power')

.proof-of-work.mt-6
  p.pb-2.opacity-50(style='font-weight: 420') Proof of Work
  a-alert.pb-5(v-if='state.current[0]', type='info')
    template(#description)
      a-spin.mr-3
      span.pb-5 Mining block {{ state.current[1] }} for transaction {{ state.current[0].slice(0, 25) }}
  p(v-else) Node {{ props.node }} not working on any block

.mempool.mt-6
  p.pb-2.opacity-50(style='font-weight: 420') Transactions in Mempool
  a-table(
    v-if='state.mempool.length > 0',
    :columns='mempoolTableCols',
    :data-source='state.mempool',
    size='small',
    :pagination='{ hideOnSinglePage: true, pageSize: 5 }'
  )
  p(v-else) No transactions in mempool

.utxos.mt-6
  p.pb-2.opacity-50(style='font-weight: 420') Blockchain UTXOs
  a-table(
    :columns='utxosTableCols',
    :data-source='state.utxos',
    size='small',
    :pagination='{ hideOnSinglePage: true, pageSize: 5 }'
  )
    template(#bodyCell='{ column, record }')
      template(v-if='column.key === "balance"')
        p {{ record['balance'].toFixed(2) }}
    template(#footer)
      p.text-right.m-0 Total: &nbsp; {{ state.utxos.reduce((a, b) => a + b.balance, 0).toFixed(2) }}
</template>
