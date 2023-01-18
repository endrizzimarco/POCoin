<script setup>
import { useWalletStore } from '@/stores/wallets'
import { computed, reactive } from 'vue'
import { message } from 'ant-design-vue'
import axios from 'axios'

const props = defineProps({
  w: String
})

const store = useWalletStore()
const formState = reactive({ amount: null, addr: null })
const available_balance = computed(() => store.wallet[props.w].available_balance)

const sendCoins = async () => {
  const r = await axios.get(`http://localhost:3000/send`, {
    params: {
      wallet: props.w,
      to_addr: formState.addr,
      amount: formState.amount
    }
  })
  const data = r.data
  r.status === 200 ? (data.includes('rejected') ? message.error(data) : message.success(data)) : message.error(data)
  formState.addr = null
  formState.amount = null
  store.getWalletStats()
}
</script>

<template lang="pug">
a-form(layout='inline', :model='formState', @finish='sendCoins')
  a-form-item(name='amount', :rules='[{ required: true, message: "Amount missing" }]')
    a-input-number(
      v-model:value='formState.amount',
      placeholder='Amount',
      :min='0.1',
      :step='1',
      :max='available_balance',
      style='max-width: 80px',
      :disabled='available_balance <= 0'
    )
  a-form-item(name='addr', :rules='[{ required: true, message: "Please input an address" }]')
    a-select(
      v-model:value='formState.addr',
      :options='store.addresses',
      placeholder='Address',
      style='width: 230px',
      :disabled='available_balance <= 0'
    )
  a-form-item
    a-button(type='primary', html-type='submit', :disabled='available_balance <= 0') Send
</template>
