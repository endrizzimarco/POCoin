<script setup>
import { ref, onMounted, computed } from 'vue'
import { message } from 'ant-design-vue'
import axios from 'axios'

const blockchain = ref([])
var scanned_height = 0

const poll_blockchain = async () => {
  const r = await (await axios.get(`http://${location.hostname}:3000/blockchain?node=n1&height=${scanned_height}`)).data
  if (r == 'up_to_date') return
  if (r.length == 1) message.success(`New block mined by ${r[0].miner}`)
  blockchain.value = blockchain.value.concat(r)
  scanned_height += r.length
}

const r_blockchain = computed(() => blockchain.value.slice().reverse())

onMounted(() => {
  poll_blockchain()
  setInterval(poll_blockchain, 1000)
})

// crimes against humanity
const toTreeData = json => {
  let treeData = []
  for (const key of Object.keys(json)) {
    let leaf = {
      key: key,
      title: json[key]
    }
    switch (key) {
      case 'height':
        continue
      case 'prev_hash':
      case 'txid':
        leaf.title = leaf?.title?.slice(0, 25)
        break
      case 'transaction':
        leaf.title = ''
        leaf.children = toTreeData(json[key])
        break
      case 'signatures':
      case 'outputs':
      case 'inputs':
        leaf.children = []
        leaf.title = ''
        for (const item of json[key]) {
          leaf.children.push({
            key: Math.random(),
            title: item?.slice(0, 35)
          })
        }
        break
    }
    if (key == 'txid') {
      treeData = [leaf, ...treeData]
    } else treeData.push(leaf)
  }
  return treeData
}
</script>

<template lang="pug">
.mx-2.overflow-y-scroll(style='height: 90vh')
  TransitionGroup(name='slide-fade')
    .px-3(v-for='(block, i) in r_blockchain', :key='block.height')
      .text-center(v-if='i != 0')
        a-divider.bg-slate-400.h-5(type='vertical', style='width: 2px')
      a-card.shadow-md.rounded-lg.trasitiom(size='small')
        template(#title)
          span.font-semibold.text-lg.ml-3 Block {{ block.height }}
        a-tree(:tree-data='toTreeData(block)')
          template(#title='{ title, key }')
            span.font-medium {{ typeof key != 'number' ? key + ': ' : '' }}
            span {{ title }}
</template>

<style>
.slide-fade-enter-active {
  transition: all 0.6s ease-out;
}

.slide-fade-enter-from,
.slide-fade-leave-to {
  transform: translateY(-200px);
  opacity: 0.5;
}

::-webkit-scrollbar {
  -webkit-appearance: none;
  width: 7px;
}
::-webkit-scrollbar-thumb {
  border-radius: 4px;
  background: linear-gradient(180deg, #28896a, 75%, #6c52eb);
  -webkit-box-shadow: 0 0 1px rgba(223, 3, 3, 0.5);
}
</style>
