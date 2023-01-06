<script setup>
import { LoadingOutlined } from '@ant-design/icons-vue'
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
div
  p.pb-3.opacity-50(style='font-weight: 420') Proof of Work 
  span.pb-5(v-if='state.current[0]')
    a-spin.mr-4
    span.pb-5 Mining block {{ state.current[1] }} for transaction: {{ state.current[0].slice(0, 25) }}
    br
  span(v-else)
    p Node {{ props.node }} not working on anything
  br
  p.pb-3.opacity-50(style='font-weight: 420') Transactions in Mempool
  a-table(
    :columns='mempoolTableCols',
    :data-source='state.mempool',
    size='small',
    :pagination='{ hideOnSinglePage: true, pageSize: 5 }'
  )
    template(#bodycell='{ column, text }')
      template(v-if='column.dataIndex === "name"')
        a {{ text }}
  br
  p.pb-3.opacity-50(style='font-weight: 420') Blockchain UTXOs
  a-table(
    :columns='utxosTableCols',
    :data-source='state.utxos',
    size='small',
    :pagination='{ hideOnSinglePage: true, pageSize: 5 }'
  )
    template(#bodycell='{ column, text }')
      template(v-if='column.dataIndex === "name"')
        a {{ text }}
</template>
