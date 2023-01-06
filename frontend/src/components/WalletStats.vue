<script setup>
import WalletSendForm from '@/components/WalletSendForm.vue'
import { QuestionCircleOutlined } from '@ant-design/icons-vue'
import { useWalletStore } from '@/stores/wallets'
import { message } from 'ant-design-vue'
import axios from 'axios'
import { computed } from 'vue'

const props = defineProps({
  wallet: String
})

const store = useWalletStore()
const state = computed(() => store.wallet[props.wallet])

const addressesTableCols = [
  {
    title: 'Address',
    dataIndex: 'address',
    key: 'address'
  },
  {
    title: 'Balance',
    dataIndex: 'balance',
    key: 'balance',
    align: 'right'
  }
]
const transactionsTableCols = [
  {
    title: 'Block',
    dataIndex: 'block',
    key: 'block',
    width: 8
  },
  {
    title: 'Type',
    dataIndex: 'type',
    key: 'type'
  },
  {
    title: 'Transaction ID',
    dataIndex: 'txid',
    key: 'txid'
  },
  {
    title: 'Amount',
    dataIndex: 'amount',
    key: 'amount',
    width: 10,
    align: 'right'
  }
]

const getAddressPubPrivKeys = (addr, addresses) => {
  return addresses.find(x => Object.keys(x)[0] === addr)[addr]
}

const generateAddress = async () => {
  const response = await axios.get('http://localhost:3000/generate_address', {
    params: {
      wallet: props.wallet
    }
  })
  response.status === 200
    ? message.success('Successfully generated address')
    : message.error('Failed to generate address')
}
</script>

<template lang="pug">
a-row
  a-col(:span='12')
    a-statistic(:value='state.total_balance', :precision='2')
      template(#title)
        span Total Balance
        a-tooltip(placement='right')
          template(#title)
            span Available UTXOs + pending change
          question-circle-outlined.ml-1(style='font-size: 14px; bottom: 1px')
  a-col(:span='12')
    a-statistic(:value='state.available_balance', :precision='2')
      template(#title)
        span Available Balance
        a-tooltip(placement='right')
          template(#title)
            span Available UTXOs only
          question-circle-outlined.ml-1(style='font-size: 14px; bottom: 1px')
.mt-5
  p.pb-3.opacity-50(style='font-weight: 420') Available UTXOs
  a-table(
    :columns='addressesTableCols',
    :data-source='state.available_utxos',
    size='small',
    :pagination='{ hideOnSinglePage: true, pageSize: 4, size: "small" }'
  )
    template(#expandedRowRender='{ record }')
      p
        span.font-medium Public key:
        span &nbsp; {{ getAddressPubPrivKeys(record['address'], state.addresses)[0].substring(0, 25) }}
      p
        span.font-medium Private key:
        span &nbsp; {{ getAddressPubPrivKeys(record['address'], state.addresses)[1].substring(0, 25) }}
  a-alert.z-50.absolute.w-full.top-5(v-if='state.next_pending', type='info', closable)
    template(#description)
      a-spin.mr-4
      span.font-semibold.underline Pending Transaction
      p.ml-12
        span.font-semibold To Address:
        span &nbsp; {{ state.next_pending[0] }}
      p.ml-12
        span.font-semibold Amount:
        span &nbsp; {{ state.next_pending[1] }}
.mt-6
  p.pb-3.opacity-50(style='font-weight: 420') Past Transactions
  a-table(
    :columns='transactionsTableCols',
    :data-source='state.history',
    size='small',
    :pagination='{ hideOnSinglePage: true, pageSize: 4, size: "small", current: curr }'
  )
.mt-1
  span.opacity-50(style='font-weight: 420') Generate Address
  a-button.ml-3(size='small', @click='generateAddress') Generate
  p.opacity-50.mt-3(style='font-weight: 420') Send coins
  WalletSendForm.mt-2(:w='props.wallet')
  p {{ curr }}
</template>
